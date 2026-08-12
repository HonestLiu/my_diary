import { NavLink } from "react-router-dom";
import { motion } from "framer-motion";
import {
  LayoutDashboard,
  PenLine,
  History,
  CalendarDays,
  Search,
  Settings,
  BookHeart,
  Plus,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/store/appStore";

const navItems = [
  { to: "/", label: "首页", icon: LayoutDashboard, end: true },
  { to: "/editor", label: "记录", icon: PenLine },
  { to: "/timeline", label: "时间轴", icon: History },
  { to: "/calendar", label: "日历", icon: CalendarDays },
  { to: "/search", label: "搜索", icon: Search },
  { to: "/on-this-day", label: "回忆", icon: BookHeart },
];

export function Sidebar({ onNewEntry }: { onNewEntry?: () => void }) {
  const collapsed = useAppStore((s) => s.sidebarCollapsed);

  return (
    <aside
      className={cn(
        "flex h-full flex-col border-r border-border bg-card/60 backdrop-blur-sm transition-[width] duration-300 ease-out",
        collapsed ? "w-[76px]" : "w-[224px]",
      )}
    >
      {/* Brand */}
      <div className="drag-region flex h-14 items-center gap-2.5 px-4">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-soft">
          <BookHeart className="h-[18px] w-[18px]" />
        </div>
        {!collapsed && (
          <div className="leading-tight">
            <div className="text-[15px] font-semibold tracking-tight">
              MyDiary
            </div>
          </div>
        )}
      </div>

      {/* Quick new entry */}
      <div className="no-drag px-3">
        <button
          type="button"
          onClick={onNewEntry}
          className={cn(
            "flex w-full items-center justify-center gap-2 rounded-xl bg-primary px-3 py-2 text-sm font-medium text-primary-foreground shadow-soft transition-colors hover:bg-primary/90",
            collapsed && "px-0",
          )}
        >
          <Plus className="h-4 w-4 shrink-0" />
          {!collapsed && <span>记录今日</span>}
        </button>
      </div>

      {/* Nav */}
      <nav className="no-drag mt-3 flex flex-1 flex-col gap-1 px-3">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              cn(
                "group relative flex items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium transition-colors",
                isActive
                  ? "text-primary"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
              )
            }
          >
            {({ isActive }) => (
              <>
                {isActive && (
                  <motion.div
                    layoutId="nav-active"
                    className="absolute inset-0 -z-10 rounded-xl bg-accent"
                    transition={{ type: "spring", stiffness: 380, damping: 30 }}
                  />
                )}
                <item.icon className="h-[18px] w-[18px] shrink-0" />
                {!collapsed && <span>{item.label}</span>}
              </>
            )}
          </NavLink>
        ))}
      </nav>

      {/* Footer */}
      <div className="no-drag flex flex-col gap-1 px-3 pb-4">
        <NavLink
          to="/settings"
          className={({ isActive }) =>
            cn(
              "flex items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium transition-colors",
              isActive
                ? "bg-accent text-accent-foreground"
                : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
            )
          }
        >
          <Settings className="h-[18px] w-[18px] shrink-0" />
          {!collapsed && <span>设置</span>}
        </NavLink>
      </div>
    </aside>
  );
}
