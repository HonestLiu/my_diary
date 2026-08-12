// MyDiary — Tauri application entry point.
//
// Phase 1: a minimal, correct Tauri v2 shell. Filesystem / dialog / sync
// plugins are added in later phases (storage P2, sync P5). The Rust side
// intentionally stays thin: the frontend (React) owns the UI and the
// local-first storage logic runs through Tauri command bridges.

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_fs::init())
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
