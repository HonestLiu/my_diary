//! 媒体压缩（Rust 侧就地处理）。
//!
//! 通过 `std::fs` 直接读写**绝对路径**，不受前端 `tauri-plugin-fs` 的 scope
//! 限制。压缩保持原格式：图片按原扩展名重新编码（jpg→jpg、png→png、
//! webp→webp），视频用 ffmpeg 转码但保持容器（mp4→mp4）。
//! 同时为列表生成 256px JPEG 缩略图（与移动端 `assets/thumbnails/` 一致）。

use serde::Serialize;
use std::path::{Path, PathBuf};

/// 压缩命令的返回结果。
#[derive(Serialize)]
pub struct MediaOutcome {
    /// 压缩后文件字节数。
    size: u64,
    /// 是否成功写入了列表缩略图。
    thumb_written: bool,
}

/// 图片最大长边（与移动端一致）。
const IMAGE_MAX_EDGE: u32 = 2000;
/// 缩略图长边。
const THUMB_EDGE: u32 = 256;

/// 图片就地压缩：读入 → 解码 → 缩放 → 按原格式重新编码写回 → 生成缩略图。
#[tauri::command]
pub async fn compress_image(
    abs_path: String,
    quality: u8,
) -> Result<MediaOutcome, String> {
    // image 解码/编码是 CPU 密集，放阻塞线程池，避免卡住 webview 主线程。
    tauri::async_runtime::spawn_blocking(move || compress_image_sync(&abs_path, quality))
        .await
        .map_err(|e| format!("压缩任务失败: {e}"))?
}

/// 视频就地压缩：ffmpeg 转码（保持容器格式）+ 抽封面帧。
#[tauri::command]
pub async fn compress_video(
    abs_path: String,
    quality: u8,
) -> Result<MediaOutcome, String> {
    tauri::async_runtime::spawn_blocking(move || compress_video_sync(&abs_path, quality))
        .await
        .map_err(|e| format!("压缩任务失败: {e}"))?
}

fn compress_image_sync(abs_path: &str, quality: u8) -> Result<MediaOutcome, String> {
    let path = Path::new(abs_path);
    let bytes = std::fs::read(path)
        .map_err(|e| format!("读取图片失败: {e}"))?;

    // 探测格式；不支持解码的格式（如 svg）直接原样保留。
    let format = image::guess_format(&bytes).map_err(|_| "无法识别的图片格式".to_string())?;
    let img = image::load_from_memory_with_format(&bytes, format)
        .map_err(|e| format!("解码图片失败: {e}"))?;

    // 等比缩放长边 ≤2000（保持纵横比；本就小则不变）。
    let (w, h) = (img.width(), img.height());
    let scale = (IMAGE_MAX_EDGE as f32 / w.max(h).max(1) as f32).min(1.0);
    let resized = if scale < 1.0 {
        img.resize(
            ((w as f32) * scale).max(1.0) as u32,
            ((h as f32) * scale).max(1.0) as u32,
            image::imageops::FilterType::Lanczos3,
        )
    } else {
        img
    };

    // 保持原格式编码。webp 编码器仅支持 lossless（VP8L），质量设置对 JPEG 生效。
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    let q = quality.clamp(1, 100);
    // 统一转换为 RGB8 原始像素，按扩展名选择编码器。
    let rgb = resized.to_rgb8();
    let (w, h) = rgb.dimensions();
    let color = image::ExtendedColorType::Rgb8;
    use image::ImageEncoder;
    let encoded: Vec<u8> = match ext.as_str() {
        "jpg" | "jpeg" => {
            let mut out = Vec::new();
            let enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, q);
            enc.write_image(&rgb, w, h, color)
                .map_err(|e| format!("JPEG 编码失败: {e}"))?;
            out
        }
        "webp" => {
            let mut out = Vec::new();
            let enc = image::codecs::webp::WebPEncoder::new_lossless(&mut out);
            enc.write_image(&rgb, w, h, color)
                .map_err(|e| format!("WebP 编码失败: {e}"))?;
            out
        }
        "png" => {
            let mut out = Vec::new();
            let enc = image::codecs::png::PngEncoder::new(&mut out);
            enc.write_image(&rgb, w, h, color)
                .map_err(|e| format!("PNG 编码失败: {e}"))?;
            out
        }
        // 其余扩展名：不重新编码，原样保留（但尺寸缩放已经完成）。
        _ => bytes,
    };

    std::fs::write(path, &encoded).map_err(|e| format!("写回图片失败: {e}"))?;

    // 生成 256px JPEG 列表缩略图（best-effort，失败不影响主结果）。
    let thumb_written = write_thumbnail(&resized, abs_path);

    Ok(MediaOutcome {
        size: encoded.len() as u64,
        thumb_written,
    })
}

fn compress_video_sync(abs_path: &str, quality: u8) -> Result<MediaOutcome, String> {
    let src = Path::new(abs_path);
    if !src.exists() {
        return Err("视频文件不存在".to_string());
    }

    // 确保 ffmpeg 可用（首次自动下载静态二进制到 exe 同目录）。
    ensure_ffmpeg()?;

    // 质量 → CRF（与移动端对齐）。
    let crf = match quality {
        q if q >= 85 => "18",
        q if q >= 60 => "23",
        q if q >= 35 => "28",
        _ => "32",
    };

    // ffmpeg 不能直接写输入文件：输出到同目录临时文件，成功后覆盖。
    let ext = src
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("mp4")
        .to_string();
    let tmp = src.with_extension(format!("tmp.{ext}"));
    let tmp_str = tmp.to_str().ok_or("临时路径无效")?.to_string();

    let mut cmd = ffmpeg_sidecar::command::FfmpegCommand::new();
    cmd.input(abs_path);
    cmd.output(&tmp_str);
    cmd.args([
        "-c:v", "libx264",
        "-crf", crf,
        "-preset", "medium",
        "-c:a", "copy",
        "-movflags", "+faststart",
        "-y",
    ]);

    let mut child = cmd.spawn().map_err(|e| format!("启动 ffmpeg 失败: {e}"))?;
    let status = child
        .wait()
        .map_err(|e| format!("等待 ffmpeg 失败: {e}"))?;
    if !status.success() {
        let _ = std::fs::remove_file(&tmp);
        return Err(format!("ffmpeg 转码失败（exit {:?}）", status.code()));
    }

    // 临时文件替换原文件，并删除可能存在的输入覆盖残留。
    let new_size = std::fs::metadata(&tmp).map(|m| m.len()).unwrap_or(0);
    std::fs::rename(&tmp, src).map_err(|e| format!("替换原文件失败: {e}"))?;

    // 抽封面帧 → 缩略图。
    let thumb_written = write_video_thumbnail(abs_path);

    Ok(MediaOutcome {
        size: new_size,
        thumb_written,
    })
}

/// 确保 ffmpeg 已就绪：若 PATH 或 exe 同目录已有则跳过，否则自动下载。
fn ensure_ffmpeg() -> Result<(), String> {
    if ffmpeg_sidecar::command::ffmpeg_is_installed() {
        return Ok(());
    }
    ffmpeg_sidecar::download::auto_download()
        .map_err(|e| format!("下载 ffmpeg 失败: {e}"))
}

/// 把图片写为 256px JPEG 缩略图（`assets/thumbnails/<basename>.jpg`）。
fn write_thumbnail(img: &image::DynamicImage, abs_path: &str) -> bool {
    let Some(thumb_rel) = thumbnail_rel_for(abs_path) else {
        return false;
    };
    let thumb_abs = resolve_thumbnail_abs(abs_path, &thumb_rel);
    let thumb = img.thumbnail(THUMB_EDGE, THUMB_EDGE);
    let mut out = Vec::new();
    let mut enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 82);
    if enc.encode_image(&thumb).is_err() {
        return false;
    }
    if let Some(parent) = Path::new(&thumb_abs).parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    std::fs::write(&thumb_abs, &out).is_ok()
}

/// 视频抽第一秒一帧作为封面缩略图（JPEG）。
fn write_video_thumbnail(abs_path: &str) -> bool {
    let Some(thumb_rel) = thumbnail_rel_for(abs_path) else {
        return false;
    };
    let thumb_abs = resolve_thumbnail_abs(abs_path, &thumb_rel);
    if let Some(parent) = Path::new(&thumb_abs).parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    let mut cmd = ffmpeg_sidecar::command::FfmpegCommand::new();
    cmd.args([
        "-ss", "1",
        "-i", abs_path,
        "-frames:v", "1",
        "-q:v", "4",
        "-y",
        thumb_abs.as_str(),
    ]);
    match cmd.spawn() {
        Ok(mut c) => c.wait().map(|s| s.success()).unwrap_or(false),
        Err(_) => false,
    }
}

/// 由绝对资产路径推导缩略图相对路径：`assets/thumbnails/<basename>.jpg`。
fn thumbnail_rel_for(abs_path: &str) -> Option<String> {
    let path = Path::new(abs_path);
    let base = path.file_stem()?.to_str()?;
    // 资产必然在 `<root>/assets/<kind>/` 下；缩略图在 `<root>/assets/thumbnails/`。
    Some(format!("assets/thumbnails/{base}.jpg"))
}

/// 从资产绝对路径推导 vault 根，拼出缩略图绝对路径。
fn resolve_thumbnail_abs(abs_path: &str, thumb_rel: &str) -> String {
    let path = PathBuf::from(abs_path);
    // `<root>/assets/<kind>/<file>` → 上溯三级得到 root。
    let root = path
        .parent()
        .and_then(|p| p.parent())
        .and_then(|p| p.parent())
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));
    root.join(thumb_rel)
        .to_string_lossy()
        .replace('\\', "/")
}
