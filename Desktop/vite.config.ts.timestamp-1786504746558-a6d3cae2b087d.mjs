// vite.config.ts
import { defineConfig } from "file:///C:/Users/Hones/WorkBuddy/2026-08-11-16-29-18/my-diary/node_modules/vite/dist/node/index.js";
import react from "file:///C:/Users/Hones/WorkBuddy/2026-08-11-16-29-18/my-diary/node_modules/@vitejs/plugin-react/dist/index.js";
import path from "node:path";
var __vite_injected_original_dirname = "C:\\Users\\Hones\\WorkBuddy\\2026-08-11-16-29-18\\my-diary";
var vite_config_default = defineConfig({
  plugins: [react()],
  // Tauri expects a fixed port and the frontend served on localhost.
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    host: false,
    hmr: {
      protocol: "ws",
      host: "localhost",
      port: 1421
    },
    watch: {
      // Tauri's Rust sources are not part of the Vite graph.
      ignored: ["**/src-tauri/**"]
    }
  },
  envPrefix: ["VITE_", "TAURI_"],
  build: {
    target: "es2021",
    outDir: "dist",
    // The sandbox intercepts fs.rmSync (trash) and fails on emptyDir; we clear
    // dist manually before builds, so disable Vite's own empty-out-dir.
    emptyOutDir: false,
    sourcemap: false,
    // Keep chunks reasonable for a desktop app.
    rollupOptions: {
      output: {
        manualChunks: {
          "react-vendor": ["react", "react-dom", "react-router-dom"],
          "motion-vendor": ["framer-motion"]
        }
      }
    }
  },
  resolve: {
    alias: {
      "@": path.resolve(__vite_injected_original_dirname, "./src")
    }
  }
});
export {
  vite_config_default as default
};
//# sourceMappingURL=data:application/json;base64,ewogICJ2ZXJzaW9uIjogMywKICAic291cmNlcyI6IFsidml0ZS5jb25maWcudHMiXSwKICAic291cmNlc0NvbnRlbnQiOiBbImNvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9kaXJuYW1lID0gXCJDOlxcXFxVc2Vyc1xcXFxIb25lc1xcXFxXb3JrQnVkZHlcXFxcMjAyNi0wOC0xMS0xNi0yOS0xOFxcXFxteS1kaWFyeVwiO2NvbnN0IF9fdml0ZV9pbmplY3RlZF9vcmlnaW5hbF9maWxlbmFtZSA9IFwiQzpcXFxcVXNlcnNcXFxcSG9uZXNcXFxcV29ya0J1ZGR5XFxcXDIwMjYtMDgtMTEtMTYtMjktMThcXFxcbXktZGlhcnlcXFxcdml0ZS5jb25maWcudHNcIjtjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfaW1wb3J0X21ldGFfdXJsID0gXCJmaWxlOi8vL0M6L1VzZXJzL0hvbmVzL1dvcmtCdWRkeS8yMDI2LTA4LTExLTE2LTI5LTE4L215LWRpYXJ5L3ZpdGUuY29uZmlnLnRzXCI7aW1wb3J0IHsgZGVmaW5lQ29uZmlnIH0gZnJvbSBcInZpdGVcIjtcbmltcG9ydCByZWFjdCBmcm9tIFwiQHZpdGVqcy9wbHVnaW4tcmVhY3RcIjtcbmltcG9ydCBwYXRoIGZyb20gXCJub2RlOnBhdGhcIjtcblxuLy8gaHR0cHM6Ly92aXRlanMuZGV2L2NvbmZpZy9cbmV4cG9ydCBkZWZhdWx0IGRlZmluZUNvbmZpZyh7XG4gIHBsdWdpbnM6IFtyZWFjdCgpXSxcbiAgLy8gVGF1cmkgZXhwZWN0cyBhIGZpeGVkIHBvcnQgYW5kIHRoZSBmcm9udGVuZCBzZXJ2ZWQgb24gbG9jYWxob3N0LlxuICBjbGVhclNjcmVlbjogZmFsc2UsXG4gIHNlcnZlcjoge1xuICAgIHBvcnQ6IDE0MjAsXG4gICAgc3RyaWN0UG9ydDogdHJ1ZSxcbiAgICBob3N0OiBmYWxzZSxcbiAgICBobXI6IHtcbiAgICAgIHByb3RvY29sOiBcIndzXCIsXG4gICAgICBob3N0OiBcImxvY2FsaG9zdFwiLFxuICAgICAgcG9ydDogMTQyMSxcbiAgICB9LFxuICAgIHdhdGNoOiB7XG4gICAgICAvLyBUYXVyaSdzIFJ1c3Qgc291cmNlcyBhcmUgbm90IHBhcnQgb2YgdGhlIFZpdGUgZ3JhcGguXG4gICAgICBpZ25vcmVkOiBbXCIqKi9zcmMtdGF1cmkvKipcIl0sXG4gICAgfSxcbiAgfSxcbiAgZW52UHJlZml4OiBbXCJWSVRFX1wiLCBcIlRBVVJJX1wiXSxcbiAgYnVpbGQ6IHtcbiAgICB0YXJnZXQ6IFwiZXMyMDIxXCIsXG4gICAgb3V0RGlyOiBcImRpc3RcIixcbiAgICAvLyBUaGUgc2FuZGJveCBpbnRlcmNlcHRzIGZzLnJtU3luYyAodHJhc2gpIGFuZCBmYWlscyBvbiBlbXB0eURpcjsgd2UgY2xlYXJcbiAgICAvLyBkaXN0IG1hbnVhbGx5IGJlZm9yZSBidWlsZHMsIHNvIGRpc2FibGUgVml0ZSdzIG93biBlbXB0eS1vdXQtZGlyLlxuICAgIGVtcHR5T3V0RGlyOiBmYWxzZSxcbiAgICBzb3VyY2VtYXA6IGZhbHNlLFxuICAgIC8vIEtlZXAgY2h1bmtzIHJlYXNvbmFibGUgZm9yIGEgZGVza3RvcCBhcHAuXG4gICAgcm9sbHVwT3B0aW9uczoge1xuICAgICAgb3V0cHV0OiB7XG4gICAgICAgIG1hbnVhbENodW5rczoge1xuICAgICAgICAgIFwicmVhY3QtdmVuZG9yXCI6IFtcInJlYWN0XCIsIFwicmVhY3QtZG9tXCIsIFwicmVhY3Qtcm91dGVyLWRvbVwiXSxcbiAgICAgICAgICBcIm1vdGlvbi12ZW5kb3JcIjogW1wiZnJhbWVyLW1vdGlvblwiXSxcbiAgICAgICAgfSxcbiAgICAgIH0sXG4gICAgfSxcbiAgfSxcbiAgcmVzb2x2ZToge1xuICAgIGFsaWFzOiB7XG4gICAgICBcIkBcIjogcGF0aC5yZXNvbHZlKF9fZGlybmFtZSwgXCIuL3NyY1wiKSxcbiAgICB9LFxuICB9LFxufSk7XG4iXSwKICAibWFwcGluZ3MiOiAiO0FBQTZWLFNBQVMsb0JBQW9CO0FBQzFYLE9BQU8sV0FBVztBQUNsQixPQUFPLFVBQVU7QUFGakIsSUFBTSxtQ0FBbUM7QUFLekMsSUFBTyxzQkFBUSxhQUFhO0FBQUEsRUFDMUIsU0FBUyxDQUFDLE1BQU0sQ0FBQztBQUFBO0FBQUEsRUFFakIsYUFBYTtBQUFBLEVBQ2IsUUFBUTtBQUFBLElBQ04sTUFBTTtBQUFBLElBQ04sWUFBWTtBQUFBLElBQ1osTUFBTTtBQUFBLElBQ04sS0FBSztBQUFBLE1BQ0gsVUFBVTtBQUFBLE1BQ1YsTUFBTTtBQUFBLE1BQ04sTUFBTTtBQUFBLElBQ1I7QUFBQSxJQUNBLE9BQU87QUFBQTtBQUFBLE1BRUwsU0FBUyxDQUFDLGlCQUFpQjtBQUFBLElBQzdCO0FBQUEsRUFDRjtBQUFBLEVBQ0EsV0FBVyxDQUFDLFNBQVMsUUFBUTtBQUFBLEVBQzdCLE9BQU87QUFBQSxJQUNMLFFBQVE7QUFBQSxJQUNSLFFBQVE7QUFBQTtBQUFBO0FBQUEsSUFHUixhQUFhO0FBQUEsSUFDYixXQUFXO0FBQUE7QUFBQSxJQUVYLGVBQWU7QUFBQSxNQUNiLFFBQVE7QUFBQSxRQUNOLGNBQWM7QUFBQSxVQUNaLGdCQUFnQixDQUFDLFNBQVMsYUFBYSxrQkFBa0I7QUFBQSxVQUN6RCxpQkFBaUIsQ0FBQyxlQUFlO0FBQUEsUUFDbkM7QUFBQSxNQUNGO0FBQUEsSUFDRjtBQUFBLEVBQ0Y7QUFBQSxFQUNBLFNBQVM7QUFBQSxJQUNQLE9BQU87QUFBQSxNQUNMLEtBQUssS0FBSyxRQUFRLGtDQUFXLE9BQU87QUFBQSxJQUN0QztBQUFBLEVBQ0Y7QUFDRixDQUFDOyIsCiAgIm5hbWVzIjogW10KfQo=
