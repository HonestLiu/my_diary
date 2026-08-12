import { Suspense, useEffect } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Sidebar } from "./Sidebar";
import { PanelLeftClose, PanelLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAppStore } from "@/store/appStore";
import { CommandPalette } from "@/components/CommandPalette";

export function AppLayout() {
  const collapsed = useAppStore((s) => s.sidebarCollapsed);
  const toggleSidebar = useAppStore((s) => s.toggleSidebar);
  const location = useLocation();

  const theme = useAppStore((s) => s.theme);

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

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-background paper-grain">
      <Sidebar />

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Title bar / collapse control */}
        <header className="no-drag flex h-14 items-center gap-2 border-b border-border/60 px-4">
          <Button
            variant="ghost"
            size="icon"
            onClick={toggleSidebar}
            aria-label="切换侧边栏"
          >
            {collapsed ? (
              <PanelLeft className="h-[18px] w-[18px]" />
            ) : (
              <PanelLeftClose className="h-[18px] w-[18px]" />
            )}
          </Button>
          <div className="text-sm font-medium text-muted-foreground">
            {breadcrumb(location.pathname)}
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

function breadcrumb(path: string): string {
  switch (true) {
    case path === "/":
      return "首页";
    case path.startsWith("/editor"):
      return "记录";
    case path.startsWith("/timeline"):
      return "时间轴";
    case path.startsWith("/calendar"):
      return "日历";
    case path.startsWith("/search"):
      return "搜索";
    case path.startsWith("/settings"):
      return "设置";
    case path.startsWith("/on-this-day"):
      return "回忆";
    default:
      return "";
  }
}
