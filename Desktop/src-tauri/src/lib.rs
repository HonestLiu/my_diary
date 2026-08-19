// MyDiary — Tauri application entry point.
//
// The Rust side intentionally stays thin: the frontend (React) owns the UI and
// the local-first storage logic runs through Tauri command bridges.

mod media;
mod sync;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            media::compress_image,
            media::compress_video,
            sync::sync_vault
        ])
        .setup(|app| {
            #[cfg(debug_assertions)]
            {
                let _ = app;
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running MyDiary");
}
