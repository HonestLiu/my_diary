import { Suspense, useEffect } from "react";
import { Outlet, useLocation, useNavigate } from "react-router-dom";
import { Sidebar } from "./Sidebar";
import {
  PanelLeftClose,
  PanelLeft,
  Search,
  PenLine,
  Sun,
  Moon,
  Monitor,
  RefreshCw,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAppStore } from "@/store/appStore";
import { CommandPalette } from "@/components/CommandPalette";
import { ExportDialog } from "@/components/export/ExportDialog";
import { applyAppearance } from "@/lib/personalization";
import { formatDateKey } from "@/lib/utils";
import type { Theme } from "@/types/journal";

export function AppLayout() {
  const collapsed = useAppStore((s) => s.sidebarCollapsed);
  const toggleSidebar = useAppStore((s) => s.toggleSidebar);
  const theme = useAppStore((s) => s.theme);
  const setTheme = useAppStore((s) => s.setTheme);
  const settings = useAppStore((s) => s.settings);
  const startNewEntry = useAppStore((s) => s.startNewEntry);
  const syncing = useAppStore((s) => s.syncing);
  const syncError = useAppStore((s) => s.syncError);
  const lastSyncAt = useAppStore((s) => s.lastSyncAt);
  const syncNow = useAppStore((s) => s.syncNow);
  const location = useLocation();
  const navigate = useNavigate();

  // Initialize the vault (load / seed) once on mount.
  useEffect(() => {
    void useAppStore.getState().initialize();
  }, []);

  // Keep the document root in sync with the user's appearance preferences
  // (theme mode, accent palette, diary font). One effect, one source of truth.
  useEffect(() => {
    applyAppearance({ theme, accent: settings.accent, font: settings.font });
  }, [theme, settings.accent, settings.font]);

  // While in "system" mode, follow OS light/dark changes live.
  useEffect(() => {
    if (theme !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () =>
      applyAppearance({ theme, accent: settings.accent, font: settings.font });
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [theme, settings.accent, settings.font]);

  // "开始记录" always opens a fresh entry dated today — today may already have
  // several, and none of them should be reopened by accident.
  const startRecording = () => {
    startNewEntry(formatDateKey());
    navigate("/editor");
  };

  const cycleTheme = () => {
    const order: Theme[] = ["light", "dark", "system"];
    const idx = order.indexOf(theme);
    const next = order[(idx + 1) % order.length] ?? "light";
    setTheme(next);
  };

  const openCommand = () =>
    window.dispatchEvent(new Event("open-command-palette"));

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-background paper-grain">
      <Sidebar onNewEntry={startRecording} />

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Desktop utility bar: search/command, vault switcher, theme, new entry.
            This replaces the old near-empty header so the top strip is actually
            doing work instead of just showing a breadcrumb. */}
        <header className="no-drag flex h-14 shrink-0 items-center gap-3 border-b border-border/60 px-3">
          <Button
            variant="ghost"
            size="icon"
            onClick={toggleSidebar}
            aria-label="切换侧边栏"
            className="shrink-0"
          >
            {collapsed ? (
              <PanelLeft className="h-[18px] w-[18px]" />
            ) : (
              <PanelLeftClose className="h-[18px] w-[18px]" />
            )}
          </Button>

          {/* Command / search trigger */}
          <button
            type="button"
            onClick={openCommand}
            className="group flex h-9 min-w-0 flex-1 items-center gap-2 rounded-lg border border-border bg-muted/40 px-3 text-sm text-muted-foreground transition-colors hover:bg-muted"
          >
            <Search className="h-4 w-4 shrink-0" />
            <span className="flex-1 truncate text-left">
              搜索日记、跳转日期或执行命令…
            </span>
            <kbd className="hidden shrink-0 rounded border border-border bg-card px-1.5 py-0.5 text-[11px] font-medium sm:inline">
              ⌘K
            </kbd>
          </button>

          {/* Right-side actions */}
          <div className="flex shrink-0 items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              onClick={() => void syncNow()}
              disabled={syncing || !settings.sync || settings.sync.provider === "none"}
              aria-label="立即同步"
              title={
                syncing
                  ? "同步中…"
                  : !settings.sync || settings.sync.provider === "none"
                    ? "同步未配置（设置中配置）"
                    : syncError
                      ? `上次同步失败：${syncError}`
                      : `立即同步${lastSyncAt ? ` · 上次 ${new Date(lastSyncAt).toLocaleTimeString()}` : ""}`
              }
              className="shrink-0"
            >
              <RefreshCw
                className={`h-[18px] w-[18px] ${syncing ? "animate-spin" : ""}`}
              />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={cycleTheme}
              aria-label="切换主题"
              title={
                theme === "system"
                  ? "跟随系统 · 点击切换"
                  : theme === "dark"
                    ? "深色 · 点击切换"
                    : "浅色 · 点击切换"
              }
            >
              {theme === "system" ? (
                <Monitor className="h-[18px] w-[18px]" />
              ) : theme === "dark" ? (
                <Sun className="h-[18px] w-[18px]" />
              ) : (
                <Moon className="h-[18px] w-[18px]" />
              )}
            </Button>
            <Button onClick={startRecording} className="gap-1.5">
              <PenLine className="h-4 w-4" />
              <span className="hidden sm:inline">开始记录</span>
            </Button>
          </div>
        </header>

        {/* Routed page. The Suspense boundary sits outside the keyed wrapper so
            a lazily-loaded chunk shows "加载中…" for the whole area instead of
            ever leaving the view blank. The `.route-fade` class (CSS keyframes)
            gives a soft enter animation that always settles at opacity:1 — it
            can't get stuck invisible the way a JS-controlled AnimatePresence
            fade occasionally did. */}
        <main className="min-h-0 flex-1 overflow-hidden">
          <Suspense
            fallback={
              <div className="flex h-full w-full items-center justify-center text-sm text-muted-foreground">
                加载中…
              </div>
            }
          >
            <div key={location.pathname} className="route-fade h-full">
              <Outlet />
            </div>
          </Suspense>
        </main>
      </div>
      <CommandPalette />
      <ExportDialog
        open={useAppStore((s) => s.exportOpen)}
        onOpenChange={(open) => useAppStore.getState().setExportOpen(open)}
      />
    </div>
  );
}
