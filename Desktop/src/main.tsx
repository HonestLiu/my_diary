import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { listenMediaProgress } from "@/lib/editor/mediaListener";
import "leaflet/dist/leaflet.css";
import "./index.css";

// 监听 Rust 侧媒体压缩进度事件（Tauri 环境；浏览器预览无此事件）。
void listenMediaProgress();

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>,
);
