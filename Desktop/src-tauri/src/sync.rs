//! 云同步（对象存储）：把原前端的 SigV4 + S3 客户端 + 双向引擎下沉到 Rust。
//!
//! 用 `reqwest` + 手写的 AWS SigV4 签名，支持 AWS S3 / Cloudflare R2 / MinIO /
//! 阿里云 OSS。本地 HTTP 的 MinIO 与 HTTPS 的 S3/R2/OSS 均可用（HTTPS 走 rustls）。
//! 前端只调用 `sync_vault` / `resolve_conflict` 命令，不再自己实现同步逻辑。
//!
//! 健壮性设计（与移动端 Dart 引擎一致，修复此前「动不动就冲突」的根因）：
//!   - 远端清单（metadata/sync.json）始终反映「桶内真实对象」，绝不写入单台设备的
//!     本地视图 —— 避免两台设备互相踩踏清单、产生虚假冲突。
//!   - 首次同步（无本机基线）不判冲突：没有共同基线就谈不上「两侧各自变更」，以
//!     远端为准采纳，本地不同版本保留为冲突安全副本。
//!   - 只对「成功对账」的路径推进本机基线；清单推送失败时回退上传路径的基线，下次
//!     同步重传并自愈，绝不把自己刚上传的内容再下载回来覆盖。
//!   - 冲突保持「待解决」状态（metadata/conflicts.json，设备本地、不进同步）：
//!     两侧副本存入 conflicts/，本地为主文件，由用户在设置页显式保留本地或采用远端。

use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
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
        // 用 ListObjectsV1（不带 list-type=2）：阿里云 OSS 的 S3 兼容接口
        // 不支持 ListObjectsV2，带 list-type=2 会直接 400；V1 被 AWS S3 /
        // R2 / MinIO / OSS 普遍支持，与移动端保持一致。
        let query = format!("prefix={prefix}");
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

/// 与移动端 `SyncEngine.shouldSync` 一致：仅同步可跨设备移植的日记内容。
///
/// `settings.json`（设备专属偏好 + 明文凭据）、`metadata/index.json`、
/// `metadata/sync.json`（本机基线）与 `conflicts/`（冲突副本）都是设备本地
/// 状态，绝不能互相覆盖 —— 否则基线、凭据、偏好会跨设备互覆。
/// 个人档案（displayName / motto / avatar）走 `profile/profile.json`，
/// 与头像文件一起在 `profile/` 下随同步迁移。
fn should_sync(rel: &str) -> bool {
    if rel == "settings.json" {
        return false;
    }
    if rel == "metadata/index.json" {
        return false;
    }
    if rel == "metadata/sync.json" {
        return false;
    }
    // 移动端把哈希缓存排除在同步外（metadata/hashes.json 属设备本地性能缓存），
    // 桌面端必须一致，否则会产生对方设备看不懂的游离对象。
    if rel == "metadata/hashes.json" {
        return false;
    }
    // 待解决冲突索引（设备本地，不跨设备同步）。
    if rel == "metadata/conflicts.json" {
        return false;
    }
    if rel.starts_with("conflicts/") {
        return false;
    }
    true
}

/// 递归遍历 vault，返回 (相对路径(/{sep}), sha256, size)。阻塞 IO 放入 spawn_blocking。
/// 只收集 `should_sync` 允许的便携内容。
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
            if !should_sync(&rel) {
                continue;
            }
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

    let remote_objects: Vec<String> = client
        .list("")
        .await?
        .into_iter()
        .filter(|p| should_sync(p))
        .collect();

    // 上次推送的远程清单：只用作「远端上次记录的状态」参照。同步循环之后，
    // 我们重新从「桶内真实对象 + 本次确认结果」构建新清单（见 new_manifest），
    // 绝不把单台设备的本地视图原样写回 —— 那正是此前两设备互相踩踏、误报冲突的根源。
    let remote_manifest = client.fetch_manifest().await;
    let old_manifest_hash: HashMap<String, String> = remote_manifest
        .as_ref()
        .map(|m| {
            m.files
                .iter()
                .filter(|f| should_sync(&f.path))
                .map(|f| (f.path.clone(), f.hash.clone()))
                .collect()
        })
        .unwrap_or_default();

    // 本机基线：上次同步完成时的本地状态，仅本机使用、不跨设备同步。
    let old_baseline = load_baseline(&root);
    let old_baseline_map: HashMap<String, (String, u64)> = old_baseline
        .map(|m| {
            m.files
                .into_iter()
                .filter(|f| should_sync(&f.path))
                .map(|f| (f.path, (f.hash, f.size)))
                .collect()
        })
        .unwrap_or_default();

    // 待解决的冲突路径：冲突发生后保持本地为主文件（两侧副本已存入 conflicts/），
    // 直到用户在设置页显式解决，避免自动同步把较新的一侧静默覆盖掉。
    let mut pending_conflicts = load_pending_conflicts(&root);

    let mut result = SyncResultDto {
        uploaded: Vec::new(),
        downloaded: Vec::new(),
        conflicts: Vec::new(),
        errors: Vec::new(),
    };

    // 本次同步后的「正确远端状态」：始终反映桶内真实对象（冲突路径记远端哈希、
    // 上传/下载路径记确认后的哈希、未触碰对象沿用上次已知哈希）。
    let mut new_manifest: HashMap<String, String> = HashMap::new();
    // 本次同步后的本机基线：只推进「成功对账」的路径；失败路径保留旧值以便重试。
    let mut new_baseline: HashMap<String, (String, u64)> = old_baseline_map.clone();
    // 本次成功上传的路径：若清单推送失败，需回退这些路径的基线，否则下次同步会
    // 把自己刚上传的内容误判成「远端变更」再下载回来覆盖。
    let mut uploaded_paths: Vec<String> = Vec::new();
    let mut changed = false;

    let all_paths: std::collections::HashSet<String> =
        local_map.keys().chain(remote_objects.iter()).cloned().collect();

    for path in all_paths {
        let l = local_map.get(&path).cloned();
        let exists = remote_objects.contains(&path);
        let prev_r = old_manifest_hash.get(&path).cloned();
        let prev_b = old_baseline_map.get(&path).cloned();
        let res = sync_one(
            &client,
            &root,
            &path,
            l,
            exists,
            prev_r,
            prev_b,
            &mut pending_conflicts,
            &mut result,
            &mut new_manifest,
            &mut new_baseline,
            &mut uploaded_paths,
            &mut changed,
        )
        .await;
        if let Err(e) = res {
            result.errors.push(format!("{path}: {e}"));
        }
    }

    if let Err(e) = save_pending_conflicts(&root, &pending_conflicts) {
        result.errors.push(format!("pending-conflicts: {e}"));
    }

    // 清单保持「桶内全量」：对本次未触碰的远端对象，沿用上次已知哈希。
    for p in &remote_objects {
        if !new_manifest.contains_key(p) {
            if let Some(rh) = old_manifest_hash.get(p) {
                new_manifest.insert(p.clone(), rh.clone());
            }
        }
    }

    let manifest = Manifest {
        version: 1,
        device_id: device_id.to_string(),
        files: new_manifest
            .iter()
            .map(|(p, h)| SyncFileDto {
                path: p.clone(),
                hash: h.clone(),
                size: 0,
                updated: now_ms(),
            })
            .collect(),
        generated_at: now_ms(),
    };

    // 先推清单、再落基线：清单写成功，上传路径的远端状态才算被确认，基线可完整推进；
    // 清单写失败则回退上传路径的基线，让下次同步重传并自愈。
    if changed {
        match client.push_manifest(&manifest).await {
            Ok(()) => {
                if let Err(e) =
                    save_baseline(&root, &baseline_manifest(&new_baseline, device_id))
                {
                    result.errors.push(format!("baseline: {e}"));
                }
            }
            Err(e) => {
                result.errors.push(format!("manifest: {e}"));
                let mut reverted = new_baseline.clone();
                for p in &uploaded_paths {
                    if let Some(ob) = old_baseline_map.get(p) {
                        reverted.insert(p.clone(), ob.clone());
                    } else {
                        reverted.remove(p);
                    }
                }
                if let Err(e) = save_baseline(&root, &baseline_manifest(&reverted, device_id)) {
                    result.errors.push(format!("baseline: {e}"));
                }
            }
        }
    } else if new_baseline != old_baseline_map {
        // 没有上传/下载/冲突，但可能记录了「首次采纳」的基线（本地与远端一致的路径），
        // 仅在确有差异时落盘。
        if let Err(e) = save_baseline(&root, &baseline_manifest(&new_baseline, device_id)) {
            result.errors.push(format!("baseline: {e}"));
        }
    }

    Ok(result)
}

fn baseline_manifest(map: &HashMap<String, (String, u64)>, device_id: &str) -> Manifest {
    Manifest {
        version: 1,
        device_id: device_id.to_string(),
        files: map
            .iter()
            .map(|(p, (h, s))| SyncFileDto {
                path: p.clone(),
                hash: h.clone(),
                size: *s,
                updated: now_ms(),
            })
            .collect(),
        generated_at: now_ms(),
    }
}

async fn read_blocking(root: &Path, path: &str) -> Result<Vec<u8>, String> {
    let root = root.to_path_buf();
    let path = path.to_string();
    tauri::async_runtime::spawn_blocking(move || local_read(&root, &path))
        .await
        .map_err(|e| e.to_string())?
}

async fn write_blocking(root: &Path, path: &str, data: &[u8]) -> Result<(), String> {
    let root = root.to_path_buf();
    let path = path.to_string();
    let data = data.to_vec();
    tauri::async_runtime::spawn_blocking(move || local_write(&root, &path, &data))
        .await
        .map_err(|e| e.to_string())?
}

#[allow(clippy::too_many_arguments)]
async fn sync_one(
    client: &S3Client,
    root: &Path,
    path: &str,
    local: Option<(String, u64)>,
    exists: bool,
    prev_r: Option<String>,
    prev_b: Option<(String, u64)>,
    pending_conflicts: &mut HashSet<String>,
    result: &mut SyncResultDto,
    new_manifest: &mut HashMap<String, String>,
    new_baseline: &mut HashMap<String, (String, u64)>,
    uploaded_paths: &mut Vec<String>,
    changed: &mut bool,
) -> Result<(), String> {
    match (local, exists) {
        (Some((lhash, lsize)), false) => {
            // 本地新增 → 上传。
            let data = read_blocking(root, path).await?;
            client.upload(path, &data).await?;
            new_baseline.insert(path.to_string(), (lhash.clone(), lsize));
            new_manifest.insert(path.to_string(), lhash);
            uploaded_paths.push(path.to_string());
            result.uploaded.push(path.to_string());
            *changed = true;
        }
        (None, true) => {
            // 远端新增 → 下载。
            let data = client.download(path).await?;
            write_blocking(root, path, &data).await?;
            let h = sha256_hex(&data);
            new_baseline.insert(path.to_string(), (h.clone(), data.len() as u64));
            new_manifest.insert(path.to_string(), h);
            result.downloaded.push(path.to_string());
            *changed = true;
        }
        (Some((lhash, lsize)), true) => {
            // 冲突尚未解决：保持本地为主文件（两侧副本已存入 conflicts/），不自动覆盖。
            if pending_conflicts.contains(path) {
                return Ok(());
            }
            // 两侧都存在：与远端清单记录一致 → 未变更。
            if prev_r.as_deref() == Some(lhash.as_str()) {
                new_baseline.insert(path.to_string(), (lhash.clone(), lsize));
                new_manifest.insert(path.to_string(), lhash);
                return Ok(());
            }
            if prev_b.is_none() {
                // 本机从未同步过该路径（首次采纳）：没有共同基线，就谈不上「两侧各自
                // 变更」，绝不能一上来就批量判冲突。以远端为准下载；本地版本若不同则
                // 保留为安全副本（conflicts/ 不参与同步，不会污染其他设备；用
                // .replaced 后缀，避免被移动端「待解决冲突」列表误判成待人工处理），
                // 但不作为需要人工处理的冲突上报。
                let local_data = read_blocking(root, path).await?;
                let data = client.download(path).await?;
                if sha256_hex(&local_data) != sha256_hex(&data) {
                    let key = conflict_key(path);
                    write_blocking(root, &conflict_path(&key, "replaced"), &local_data).await?;
                }
                write_blocking(root, path, &data).await?;
                let h = sha256_hex(&data);
                new_baseline.insert(path.to_string(), (h.clone(), data.len() as u64));
                new_manifest.insert(path.to_string(), h);
                result.downloaded.push(path.to_string());
                *changed = true;
                return Ok(());
            }
            let (pbhash, _) = prev_b.as_ref().unwrap();
            let local_changed = pbhash != &lhash;
            // 远端是否变更 = 本次清单哈希 与 本机基线哈希 是否不同；清单缺失时无法
            // 证明远端未变，保守视为已变（避免静默覆盖），但这只影响单个文件。
            let remote_changed = prev_r.is_none() || Some(pbhash.as_str()) != prev_r.as_deref();
            if local_changed && remote_changed {
                // 两侧自上次同步起都变更 → 冲突：写冲突副本，绝不覆盖。
                let local_data = read_blocking(root, path).await?;
                let remote_data = client.download(path).await?;
                let key = conflict_key(path);
                write_blocking(root, &conflict_path(&key, "local"), &local_data).await?;
                write_blocking(root, &conflict_path(&key, "remote"), &remote_data).await?;
                // 清单必须反映桶内真实状态：记远端哈希，而不是被踩踏成本地视图。
                let rh = sha256_hex(&remote_data);
                new_baseline.insert(path.to_string(), (lhash.clone(), lsize));
                new_manifest.insert(path.to_string(), rh);
                pending_conflicts.insert(path.to_string());
                result.conflicts.push(path.to_string());
                *changed = true;
            } else if local_changed {
                let data = read_blocking(root, path).await?;
                client.upload(path, &data).await?;
                new_baseline.insert(path.to_string(), (lhash.clone(), lsize));
                new_manifest.insert(path.to_string(), lhash);
                uploaded_paths.push(path.to_string());
                result.uploaded.push(path.to_string());
                *changed = true;
            } else {
                // 仅远端变更（或清单缺失但本机有基线）→ 下载，远端在此处为准。
                let data = client.download(path).await?;
                write_blocking(root, path, &data).await?;
                let h = sha256_hex(&data);
                new_baseline.insert(path.to_string(), (h.clone(), data.len() as u64));
                new_manifest.insert(path.to_string(), h);
                result.downloaded.push(path.to_string());
                *changed = true;
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

fn pending_conflicts_path(root: &Path) -> PathBuf {
    root.join("metadata/conflicts.json")
}

fn load_pending_conflicts(root: &Path) -> HashSet<String> {
    let p = pending_conflicts_path(root);
    let Ok(data) = std::fs::read(&p) else {
        return HashSet::new();
    };
    serde_json::from_slice::<Vec<String>>(&data)
        .unwrap_or_default()
        .into_iter()
        .collect()
}

fn save_pending_conflicts(root: &Path, pending: &HashSet<String>) -> Result<(), String> {
    let p = pending_conflicts_path(root);
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let mut list: Vec<String> = pending.iter().cloned().collect();
    list.sort();
    let data = serde_json::to_vec_pretty(&list).map_err(|e| e.to_string())?;
    std::fs::write(&p, data).map_err(|e| e.to_string())
}

/// 解决一个已检测到的冲突：`resolution` 为 "local"（保留本地）或 "remote"（采用远端）。
/// 前端在设置页调用 `invoke("resolve_conflict", { vaultRoot, config, path, resolution })`。
#[tauri::command]
pub async fn resolve_conflict(
    vault_root: String,
    config: SyncConfigDto,
    path: String,
    resolution: String,
) -> Result<(), String> {
    if config.provider == "none" {
        return Err("未选择同步服务商（provider=none）".to_string());
    }
    if resolution != "local" && resolution != "remote" {
        return Err(format!("未知的冲突解决方式: {resolution}"));
    }
    let root = PathBuf::from(vault_root.trim_end_matches('/').replace('\\', "/"));
    if !root.exists() {
        return Err(format!("vault 根目录不存在: {root:?}"));
    }
    let client = S3Client::new(&config)?;
    let device_id = "desktop";

    // 先把该路径收敛到所选一侧。
    if resolution == "local" {
        let data = read_blocking(&root, &path).await?;
        client.upload(&path, &data).await?;
    } else {
        let data = client.download(&path).await?;
        write_blocking(&root, &path, &data).await?;
    }

    // 移除两侧冲突副本。
    let key = conflict_key(&path);
    let _ = std::fs::remove_file(root.join(
        conflict_path(&key, "local").replace('/', std::path::MAIN_SEPARATOR_STR),
    ));
    let _ = std::fs::remove_file(root.join(
        conflict_path(&key, "remote").replace('/', std::path::MAIN_SEPARATOR_STR),
    ));

    // 从待解决列表摘除。
    let mut pending = load_pending_conflicts(&root);
    pending.remove(&path);
    save_pending_conflicts(&root, &pending)?;

    let bytes = std::fs::read(root.join(path.replace('/', std::path::MAIN_SEPARATOR_STR)))
        .map_err(|e| e.to_string())?;
    let hash = sha256_hex(&bytes);
    let size = bytes.len() as u64;

    // 刷新本机基线（已解决状态）。
    let mut baseline = load_baseline(&root).unwrap_or(Manifest {
        version: 1,
        device_id: device_id.to_string(),
        files: Vec::new(),
        generated_at: now_ms(),
    });
    baseline.files.retain(|f| f.path != path);
    baseline.files.push(SyncFileDto {
        path: path.clone(),
        hash: hash.clone(),
        size,
        updated: now_ms(),
    });
    save_baseline(&root, &baseline)?;

    // 让远端清单也反映已解决状态（否则下次同步会以为远端又变了）。
    let mut manifest = client.fetch_manifest().await.unwrap_or(Manifest {
        version: 1,
        device_id: device_id.to_string(),
        files: Vec::new(),
        generated_at: now_ms(),
    });
    manifest.files.retain(|f| f.path != path);
    manifest.files.push(SyncFileDto {
        path: path.clone(),
        hash,
        size,
        updated: now_ms(),
    });
    client
        .push_manifest(&manifest)
        .await
        .map_err(|e| format!("冲突已解决，但远端清单刷新失败: {e}"))
}
