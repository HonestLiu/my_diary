import { Suspense, useEffect, useState } from "react";
import { Outlet, useLocation, useNavigate } from "react-router-dom";
import { Sidebar } from "./Sidebar";
import {
  PanelLeftClose,
  PanelLeft,
  Search,
  PenLine,
  Sun,
  Moon,
  Layers,
  ChevronDown,
  Check,
  Settings as SettingsIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAppStore } from "@/store/appStore";
import { CommandPalette } from "@/components/CommandPalette";
import { formatDateKey } from "@/lib/utils";
import { cn } from "@/lib/utils";

export function AppLayout() {
  const collapsed = useAppStore((s) => s.sidebarCollapsed);
  const toggleSidebar = useAppStore((s) => s.toggleSidebar);
  const theme = useAppStore((s) => s.theme);
  const setTheme = useAppStore((s) => s.setTheme);
  const setActiveDate = useAppStore((s) => s.setActiveDate);
  const location = useLocation();
  const navigate = useNavigate();

  // Initialize the vault (load / seed) once on mount.
  useEffect(() => {
    void useAppStore.getState().initialize();
  }, []);

  // Apply the light/dark theme to the document root.
  useEffect(() => {
    const root = document.documentElement;
    if (theme === "dark") root.classList.add("dark");
    else root.classList.remove("dark");
  }, [theme]);

  const startRecording = () => {
    const key = formatDateKey();
    setActiveDate(key);
    navigate(`/editor?date=${key}`);
  };

  const toggleTheme = () =>
    setTheme(theme === "dark" ? "light" : "dark");

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
            <VaultSwitcher />
            <Button
              variant="ghost"
              size="icon"
              onClick={toggleTheme}
              aria-label="切换主题"
              title="切换浅色 / 深色"
            >
              {theme === "dark" ? (
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
    </div>
  );
}

/** Compact vault switcher dropdown shown in the top bar. */
function VaultSwitcher() {
  const vaults = useAppStore((s) => s.vaults);
  const activeVaultId = useAppStore((s) => s.activeVaultId);
  const switchVault = useAppStore((s) => s.switchVault);
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);

  const current = vaults.find((v) => v.id === activeVaultId);

  return (
    <div className="relative">
      <Button
        variant="ghost"
        size="sm"
        onClick={() => setOpen((o) => !o)}
        className="h-9 gap-1.5 px-2.5 text-foreground"
        title="切换日记库"
      >
        <Layers className="h-4 w-4 text-muted-foreground" />
        <span className="max-w-[120px] truncate">
          {current?.name ?? "日记库"}
        </span>
        <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" />
      </Button>

      {open && (
        <>
          <div
            className="fixed inset-0 z-40"
            onClick={() => setOpen(false)}
            aria-hidden
          />
          <div className="absolute right-0 z-50 mt-2 w-56 overflow-hidden rounded-xl border border-border bg-card p-1.5 shadow-2xl">
            <div className="px-3 py-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
              日记库
            </div>
            {vaults.map((v) => (
              <button
                key={v.id}
                type="button"
                onClick={() => {
                  void switchVault(v.id);
                  setOpen(false);
                }}
                className={cn(
                  "flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors hover:bg-muted",
                  v.id === activeVaultId ? "text-primary" : "text-foreground",
                )}
              >
                <Layers className="h-4 w-4 shrink-0" />
                <span className="flex-1 truncate text-left">{v.name}</span>
                {v.id === activeVaultId && (
                  <Check className="h-4 w-4 shrink-0" />
                )}
              </button>
            ))}
            <div className="my-1 h-px bg-border" />
            <button
              type="button"
              onClick={() => {
                setOpen(false);
                navigate("/settings");
              }}
              className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-muted-foreground transition-colors hover:bg-muted"
            >
              <SettingsIcon className="h-4 w-4 shrink-0" />
              管理日记库
            </button>
          </div>
        </>
      )}
    </div>
  );
}
