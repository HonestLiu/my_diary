//! 云同步（对象存储）：把原前端的 SigV4 + S3 客户端 + 双向引擎下沉到 Rust。
//!
//! 用 `reqwest` + 手写的 AWS SigV4 签名，支持 AWS S3 / Cloudflare R2 / MinIO /
//! 阿里云 OSS。本地 HTTP 的 MinIO 与 HTTPS 的 S3/R2/OSS 均可用（HTTPS 走 rustls）。
//! 前端只调用 `sync_vault` 命令，不再自己实现同步逻辑。

use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

type HmacSha256 = Hmac<Sha256>;

/// 前端 `SyncConfig` 的命令参数（只取同步所需字段）。
/// 前端用 camelCase（accessKey / secretKey / pathStyle），故用 rename_all 对齐。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncConfigDto {
    #[allow(dead_code)]
    pub enabled: bool,
    #[allow(dead_code)]
    pub provider: String,
    pub endpoint: Option<String>,
    pub bucket: Option<String>,
    pub region: Option<String>,
    pub access_key: Option<String>,
    pub secret_key: Option<String>,
    pub path_style: Option<bool>,
}

/// 同步结果（对应前端 `SyncResult`）。
#[derive(Debug, Serialize)]
pub struct SyncResultDto {
    pub uploaded: Vec<String>,
    pub downloaded: Vec<String>,
    pub conflicts: Vec<String>,
    pub errors: Vec<String>,
}

/// 远端/本地清单里的一条文件记录。
#[derive(Debug, Serialize, Deserialize)]
struct SyncFileDto {
    path: String,
    hash: String,
    size: u64,
    updated: u64,
}

/// 与 `metadata/sync.json` 对应的清单结构。
#[derive(Debug, Serialize, Deserialize)]
struct Manifest {
    #[allow(dead_code)]
    version: u8,
    #[allow(dead_code)]
    device_id: String,
    files: Vec<SyncFileDto>,
    #[allow(dead_code)]
    generated_at: u64,
}

/// S3 兼容客户端（SigV4 over reqwest）。
struct S3Client {
    endpoint: String, // 含 scheme，如 http://localhost:9000
    bucket: String,
    region: String,
    access_key: String,
    secret_key: String,
    path_style: bool,
    http: reqwest::Client,
}

impl S3Client {
    fn new(cfg: &SyncConfigDto) -> Result<Self, String> {
        let endpoint = cfg
            .endpoint
            .clone()
            .ok_or("endpoint 必填")?
            .trim_end_matches('/')
            .to_string();
        let bucket = cfg.bucket.clone().ok_or("bucket 必填")?;
        let access_key = cfg.access_key.clone().ok_or("accessKey 必填")?;
        let secret_key = cfg.secret_key.clone().ok_or("secretKey 必填")?;
        let region = cfg.region.clone().unwrap_or_else(|| "us-east-1".to_string());
        let path_style = cfg.path_style.unwrap_or(false);
        let http = reqwest::Client::builder()
            // MinIO / R2 / OSS 的 API 端口都是 HTTP/1.1；强制 1.1 避免任何
            // HTTP/2 协商问题。
            .http1_only()
            .timeout(std::time::Duration::from_secs(60))
            .build()
            .map_err(|e| format!("HTTP 客户端创建失败: {e}"))?;
        Ok(Self {
            endpoint,
            bucket,
            region,
            access_key,
            secret_key,
            path_style,
            http,
        })
    }

    /// 返回 (请求 URL, 用于签名的 host, 用于签名的 canonical path)。
    fn url_and_parts(&self, key: &str) -> (String, String, String) {
        let base = self.endpoint.as_str();
        let canonical_key = key.trim_start_matches('/');
        if self.path_style {
            let url = format!("{base}/{}/{}", self.bucket, canonical_key);
            let host = strip_scheme(base);
            let path = format!("/{}/{}", self.bucket, canonical_key);
            (url, host, path)
        } else {
            // 虚拟主机风格：https://<bucket>.<host>/<key>
            let host = format!("{}.{}", self.bucket, strip_scheme(base));
            let url = format!("https://{}/{}", host, canonical_key);
            let path = format!("/{}", canonical_key);
            (url, host, path)
        }
    }

    /// 发一次签名请求，返回 (状态码, 响应体 bytes)。
    async fn request(
        &self,
        method: reqwest::Method,
        key: &str,
        body: Option<Vec<u8>>,
        query: Option<&str>,
        content_type: Option<&str>,
    ) -> Result<(u16, Vec<u8>), String> {
        let (url, host, canonical_path) = self.url_and_parts(key);
        let payload = body.clone().unwrap_or_default();
        let payload_hash = sha256_hex(&payload);

        // 规范化查询：拆分 -> RFC3986 编码 -> 按编码后的 key 排序 -> 重新拼接。
        let (canonical_query, send_query) = match query {
            Some(q) => {
                let mut pairs: Vec<(String, String)> = Vec::new();
                for part in q.split('&') {
                    if part.is_empty() {
                        continue;
                    }
                    let (k, v) = match part.split_once('=') {
                        Some((k, v)) => (k.to_string(), v.to_string()),
                        None => (part.to_string(), String::new()),
                    };
                    pairs.push((uri_encode(&k, true), uri_encode(&v, true)));
                }
                pairs.sort_by(|a, b| a.0.cmp(&b.0));
                let joined = pairs
                    .iter()
                    .map(|(k, v)| format!("{k}={v}"))
                    .collect::<Vec<_>>()
                    .join("&");
                (joined.clone(), joined)
            }
            None => (String::new(), String::new()),
        };

        let send_url = if send_query.is_empty() {
            url
        } else {
            format!("{url}?{send_query}")
        };

        // 规范化头（按字典序签名）。
        let mut headers_to_sign: Vec<(String, String)> = vec![
            ("host".to_string(), host.clone()),
            ("x-amz-content-sha256".to_string(), payload_hash.clone()),
        ];
        if let Some(ct) = content_type {
            headers_to_sign.push(("content-type".to_string(), ct.to_string()));
        }
        // x-amz-date 稍后加入（需要 amzdate 参与规范化）。
        let amz_date = amz_date_now();
        headers_to_sign.push(("x-amz-date".to_string(), amz_date.clone()));
        headers_to_sign.sort_by(|a, b| a.0.cmp(&b.0));

        let signed_headers = headers_to_sign
            .iter()
            .map(|(k, _)| k.clone())
            .collect::<Vec<_>>()
            .join(";");
        let canonical_headers = headers_to_sign
            .iter()
            .map(|(k, v)| format!("{k}:{}\n", v.trim()))
            .collect::<String>();

        let canonical_uri = uri_encode(canonical_path.as_str(), false);
        let canonical_request = format!(
            "{}\n{}\n{}\n{}\n{}\n{}",
            method.as_str(),
            canonical_uri,
            canonical_query,
            canonical_headers,
            signed_headers,
            payload_hash
        );

        let scope = format!(
            "{}/{}/s3/aws4_request",
            &amz_date[0..8],
            self.region
        );
        let string_to_sign = format!(
            "AWS4-HMAC-SHA256\n{}\n{}\n{}",
            amz_date,
            scope,
            sha256_hex(canonical_request.as_bytes())
        );

        let signing_key = signing_key(&self.secret_key, &amz_date[0..8], &self.region);
        let signature = hmac_hex(&signing_key, string_to_sign.as_bytes());
        let authorization = format!(
            "AWS4-HMAC-SHA256 Credential={}/{}, SignedHeaders={}, Signature={}",
            self.access_key, scope, signed_headers, signature
        );

        let mut req = self
            .http
            .request(method, &send_url)
            .header("Host", &host)
            .header("x-amz-content-sha256", &payload_hash)
            .header("x-amz-date", &amz_date)
            .header("Authorization", authorization);
        if let Some(ct) = content_type {
            req = req.header("Content-Type", ct);
        }
        if let Some(b) = body {
            req = req.body(b);
        }

        let resp = req.send().await.map_err(|e| {
            let mut msg = format!("请求 {key} 失败: {e}");
            if e.is_connect() {
                msg.push_str(
                    "（无法建立连接：请确认 endpoint 可达。若填的是本机局域网 IP（如 192.168.x.x），\
改填 127.0.0.1 或 localhost 往往即可——本机用局域网 IP 访问自己常被防火墙拦截，\
而 127.0.0.1 环路不受影响。）",
                );
            }
            msg
        })?;
        let status = resp.status().as_u16();
        let bytes = resp
            .bytes()
            .await
            .map_err(|e| format!("读取 {key} 响应失败: {e}"))?
            .to_vec();
        Ok((status, bytes))
    }

    async fn upload(&self, key: &str, data: &[u8]) -> Result<(), String> {
        let (status, _) = self
            .request(
                reqwest::Method::PUT,
                key,
                Some(data.to_vec()),
                None,
                Some("application/octet-stream"),
            )
            .await?;
        if (200..300).contains(&status) {
            Ok(())
        } else {
            Err(format!("上传 {key} 失败 (HTTP {status})"))
        }
    }

    async fn download(&self, key: &str) -> Result<Vec<u8>, String> {
        let (status, body) = self.request(reqwest::Method::GET, key, None, None, None).await?;
        if (200..300).contains(&status) {
            Ok(body)
        } else {
            Err(format!("下载 {key} 失败 (HTTP {status})"))
        }
    }

    /// 列出对象（按前缀）。返回 key 列表。
    async fn list(&self, prefix: &str) -> Result<Vec<String>, String> {
        // 注意：传「原始」前缀，request() 内部会对查询参数做 RFC3986 编码，
        // 避免二次编码。
        let query = format!("list-type=2&prefix={prefix}");
        let (status, body) = self
            .request(reqwest::Method::GET, "", None, Some(&query), None)
            .await?;
        if !(200..300).contains(&status) {
            return Err(format!("列举对象失败 (HTTP {status})"));
        }
        let text = String::from_utf8_lossy(&body);
        let mut keys = Vec::new();
        let re = regex_less_extract_keys(&text);
        keys.extend(re);
        keys.sort();
        Ok(keys)
    }

    async fn fetch_manifest(&self) -> Option<Manifest> {
        match self.download("metadata/sync.json").await {
            Ok(data) => serde_json::from_slice(&data).ok(),
            Err(_) => None,
        }
    }

    async fn push_manifest(&self, manifest: &Manifest) -> Result<(), String> {
        let data = serde_json::to_vec_pretty(manifest).map_err(|e| e.to_string())?;
        self.upload("metadata/sync.json", &data).await
    }
}

/// 极简从 ListBucketResult XML 抽取 <Key> 的辅助（避免引入 xml 依赖）。
fn regex_less_extract_keys(xml: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = xml;
    while let Some(start) = rest.find("<Key>") {
        let after = &rest[start + 5..];
        if let Some(end) = after.find("</Key>") {
            out.push(after[..end].to_string());
            rest = &after[end + 6..];
        } else {
            break;
        }
    }
    out
}

fn strip_scheme(url: &str) -> String {
    url.replace("https://", "")
        .replace("http://", "")
        .trim_end_matches('/')
        .to_string()
}

/// RFC 3986 编码：非保留字符（A-Za-z0-9-_.~）原样保留，其余 %XX（大写）。
/// `encode_slash=false` 时连 '/' 也保留（用于 path）。
fn uri_encode(s: &str, encode_slash: bool) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        let c = b as char;
        if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' || c == '~' {
            out.push(c);
        } else if c == '/' && !encode_slash {
            out.push('/');
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

fn amz_date_now() -> String {
    // AWS SigV4 时间戳：20210818T140503Z（UTC）
    let now = chrono::Utc::now();
    now.format("%Y%m%dT%H%M%SZ").to_string()
}

fn hmac_hex(key: &[u8], data: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC accepts any key length");
    mac.update(data);
    hex::encode(mac.finalize().into_bytes())
}

/// AWS SigV4 签名密钥：HMAC 链路 AWS4+secret -> date -> region -> s3 -> aws4_request。
fn signing_key(secret: &str, date_stamp: &str, region: &str) -> Vec<u8> {
    let k0 = format!("AWS4{secret}").into_bytes();
    let k1 = hmac_bytes(&k0, date_stamp.as_bytes());
    let k2 = hmac_bytes(&k1, region.as_bytes());
    let k3 = hmac_bytes(&k2, b"s3");
    hmac_bytes(&k3, b"aws4_request")
}

fn hmac_bytes(key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC accepts any key length");
    mac.update(data);
    mac.finalize().into_bytes().to_vec()
}

/// 递归遍历 vault，返回 (相对路径(/{sep}), sha256, size)。阻塞 IO 放入 spawn_blocking。
fn list_local(root: &Path) -> Result<Vec<(String, String, u64)>, String> {
    let mut out = Vec::new();
    walk(root, root, &mut out)?;
    Ok(out)
}

fn walk(root: &Path, dir: &Path, out: &mut Vec<(String, String, u64)>) -> Result<(), String> {
    let entries = std::fs::read_dir(dir).map_err(|e| format!("读取目录失败 {dir:?}: {e}"))?;
    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if path.is_dir() {
            walk(root, &path, out)?;
        } else if path.is_file() {
            let data = std::fs::read(&path).map_err(|e| format!("读取文件失败 {path:?}: {e}"))?;
            let rel = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            let hash = sha256_hex(&data);
            out.push((rel, hash, data.len() as u64));
        }
    }
    Ok(())
}

fn local_read(root: &Path, rel: &str) -> Result<Vec<u8>, String> {
    let p = root.join(rel.replace('/', std::path::MAIN_SEPARATOR_STR));
    std::fs::read(&p).map_err(|e| format!("读取 {rel} 失败: {e}"))
}

fn local_write(root: &Path, rel: &str, data: &[u8]) -> Result<(), String> {
    let p = root.join(rel.replace('/', std::path::MAIN_SEPARATOR_STR));
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("创建目录失败: {e}"))?;
    }
    std::fs::write(&p, data).map_err(|e| format!("写入 {rel} 失败: {e}"))
}

/// 同步入口命令：前端调用 `invoke("sync_vault", { vaultRoot, config })`。
#[tauri::command]
pub async fn sync_vault(
    vault_root: String,
    config: SyncConfigDto,
) -> Result<SyncResultDto, String> {
    if config.provider == "none" {
        return Err("未选择同步服务商（provider=none）".to_string());
    }
    let root = PathBuf::from(vault_root.trim_end_matches('/').replace('\\', "/"));
    if !root.exists() {
        return Err(format!("vault 根目录不存在: {root:?}"));
    }

    let client = S3Client::new(&config)?;
    let device_id = "desktop"; // 单设备场景，baseline 仅作去重参考

    let local = tauri::async_runtime::spawn_blocking({
        let root = root.clone();
        move || list_local(&root)
    })
    .await
    .map_err(|e| e.to_string())??;

    let local_map: HashMap<String, (String, u64)> = local
        .into_iter()
        .map(|(p, h, s)| (p, (h, s)))
        .collect();

    let remote_objects = client.list("").await?;
    let remote_manifest = client.fetch_manifest().await;
    let remote_hash: HashMap<String, String> = remote_manifest
        .as_ref()
        .map(|m| m.files.iter().map(|f| (f.path.clone(), f.hash.clone())).collect())
        .unwrap_or_default();

    // 读取上一次同步基线（用于判断两侧是否各自变更）。
    let baseline = load_baseline(&root);
    let base_map: HashMap<String, String> =
        baseline.map(|m| m.files.iter().map(|f| (f.path.clone(), f.hash.clone())).collect()).unwrap_or_default();

    let mut result = SyncResultDto {
        uploaded: Vec::new(),
        downloaded: Vec::new(),
        conflicts: Vec::new(),
        errors: Vec::new(),
    };

    let all_paths: std::collections::HashSet<String> =
        local_map.keys().chain(remote_objects.iter()).cloned().collect();

    for path in all_paths {
        let l = local_map.get(&path).cloned();
        let r_exists = remote_objects.contains(&path);
        let r_hash = remote_hash.get(&path).cloned();
        let b = base_map.get(&path).cloned();
        let res = sync_one(
            &client,
            &root,
            &path,
            l,
            r_exists,
            r_hash,
            b,
            device_id,
            &mut result,
        )
        .await;
        if let Err(e) = res {
            result.errors.push(format!("{path}: {e}"));
        }
    }

    // 更新基线 + 推送清单。
    let manifest = Manifest {
        version: 1,
        device_id: device_id.to_string(),
        files: local_map
            .iter()
            .map(|(p, (h, s))| SyncFileDto {
                path: p.clone(),
                hash: h.clone(),
                size: *s,
                updated: now_ms(),
            })
            .collect(),
        generated_at: now_ms(),
    };
    if let Err(e) = save_baseline(&root, &manifest) {
        result.errors.push(format!("baseline: {e}"));
    }
    if let Err(e) = client.push_manifest(&manifest).await {
        result.errors.push(format!("manifest: {e}"));
    }

    Ok(result)
}

#[allow(clippy::too_many_arguments)]
async fn sync_one(
    client: &S3Client,
    root: &Path,
    path: &str,
    local: Option<(String, u64)>,
    remote_exists: bool,
    remote_hash: Option<String>,
    baseline_hash: Option<String>,
    _device_id: &str,
    result: &mut SyncResultDto,
) -> Result<(), String> {
    match (local, remote_exists) {
        (Some(_), false) => {
            // 本地新增 → 上传
            let data = tauri::async_runtime::spawn_blocking({
                let root = root.to_path_buf();
                let path = path.to_string();
                move || local_read(&root, &path)
            })
            .await
            .map_err(|e| e.to_string())??;
            client.upload(path, &data).await?;
            result.uploaded.push(path.to_string());
        }
        (None, true) => {
            // 远端新增 → 下载
            let data = client.download(path).await?;
            tauri::async_runtime::spawn_blocking({
                let root = root.to_path_buf();
                let path = path.to_string();
                let data = data.clone();
                move || local_write(&root, &path, &data)
            })
            .await
            .map_err(|e| e.to_string())??;
            result.downloaded.push(path.to_string());
        }
        (Some((lhash, _)), true) => {
            if let Some(rh) = &remote_hash {
                if *rh == lhash {
                    return Ok(()); // 一致
                }
            }
            let local_changed = baseline_hash.as_deref() != Some(lhash.as_str());
            // 无远端清单或基线无法证明远端未变 → 保守认为远端也变了（避免静默覆盖）。
            let remote_changed = remote_hash.is_none() || baseline_hash.as_deref() != remote_hash.as_deref();
            if local_changed && remote_changed {
                // 两侧都变 → 冲突：写冲突副本，绝不覆盖。
                let local_data = tauri::async_runtime::spawn_blocking({
                    let root = root.to_path_buf();
                    let path = path.to_string();
                    move || local_read(&root, &path)
                })
                .await
                .map_err(|e| e.to_string())??;
                let remote_data = client.download(path).await?;
                let key = conflict_key(path);
                tauri::async_runtime::spawn_blocking({
                    let root = root.to_path_buf();
                    let key = key.clone();
                    let local_data = local_data.clone();
                    let remote_data = remote_data.clone();
                    move || {
                        local_write(&root, &conflict_path(&key, "local"), &local_data)
                            .and_then(|_| local_write(&root, &conflict_path(&key, "remote"), &remote_data))
                    }
                })
                .await
                .map_err(|e| e.to_string())??;
                result.conflicts.push(path.to_string());
            } else if local_changed {
                let data = tauri::async_runtime::spawn_blocking({
                    let root = root.to_path_buf();
                    let path = path.to_string();
                    move || local_read(&root, &path)
                })
                .await
                .map_err(|e| e.to_string())??;
                client.upload(path, &data).await?;
                result.uploaded.push(path.to_string());
            } else {
                let data = client.download(path).await?;
                tauri::async_runtime::spawn_blocking({
                    let root = root.to_path_buf();
                    let path = path.to_string();
                    let data = data.clone();
                    move || local_write(&root, &path, &data)
                })
                .await
                .map_err(|e| e.to_string())??;
                result.downloaded.push(path.to_string());
            }
        }
        (None, false) => { /* 都不存在，跳过 */ }
    }
    Ok(())
}

fn conflict_key(path: &str) -> String {
    // 优先用文件名（条目同名），否则用路径扁平化。
    if let Some(base) = path.rsplit('/').next() {
        if base.ends_with(".md") {
            return base.trim_end_matches(".md").to_string();
        }
    }
    path.replace('/', "_").replace(".md", "")
}

fn conflict_path(key: &str, side: &str) -> String {
    format!("conflicts/{key}.{side}.md")
}

fn baseline_path(root: &Path) -> PathBuf {
    root.join("metadata/sync.json")
}

fn load_baseline(root: &Path) -> Option<Manifest> {
    let p = baseline_path(root);
    let data = std::fs::read(&p).ok()?;
    serde_json::from_slice(&data).ok()
}

fn save_baseline(root: &Path, m: &Manifest) -> Result<(), String> {
    let p = baseline_path(root);
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let data = serde_json::to_vec_pretty(m).map_err(|e| e.to_string())?;
    std::fs::write(&p, data).map_err(|e| e.to_string())
}

fn now_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
