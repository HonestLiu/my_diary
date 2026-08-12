import * as React from "react";
import { useEffect, useMemo, useState, type ComponentType } from "react";
import { useNavigate } from "react-router-dom";
import {
  LayoutDashboard,
  PenLine,
  History,
  CalendarDays,
  Search,
  Settings,
  Stars,
  Download,
  Sun,
  Moon,
  CornerDownLeft,
  Layers,
} from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { formatDateKey } from "@/lib/utils";
import { exportHtml } from "@/lib/export";
import { cn } from "@/lib/utils";

interface Cmd {
  id: string;
  label: string;
  hint?: string;
  icon: ComponentType<{ className?: string }>;
  group: string;
  run: () => void;
}

/**
 * Zero-dependency command palette (⌘K / Ctrl+K).
 * Navigates, opens a specific date, toggles theme, exports, and searches
 * entries by title — all from the keyboard.
 */
export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);

  const navigate = useNavigate();
  const entries = useAppStore((s) => s.entries);
  const setActiveDate = useAppStore((s) => s.setActiveDate);
  const setTheme = useAppStore((s) => s.setTheme);
  const theme = useAppStore((s) => s.theme);
  const vaults = useAppStore((s) => s.vaults);
  const activeVaultId = useAppStore((s) => s.activeVaultId);
  const switchVault = useAppStore((s) => s.switchVault);

  // Global ⌘K / Ctrl+K toggle.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setOpen((o) => !o);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (open) {
      setQuery("");
      setActive(0);
    }
  }, [open]);

  const openEntry = (date: string) => {
    setActiveDate(date);
    setOpen(false);
    navigate("/editor");
  };

  const cmds = useMemo<Cmd[]>(() => {
    const nav: Cmd[] = [
      { id: "home", label: "首页", icon: LayoutDashboard, group: "导航", run: () => navigate("/") },
      { id: "editor", label: "记录 · 今天", icon: PenLine, group: "导航", run: () => openEntry(formatDateKey()) },
      { id: "timeline", label: "时间轴", icon: History, group: "导航", run: () => navigate("/timeline") },
      { id: "calendar", label: "日历", icon: CalendarDays, group: "导航", run: () => navigate("/calendar") },
      { id: "search", label: "搜索", icon: Search, group: "导航", run: () => navigate("/search") },
      { id: "memory", label: "回忆 · 一年前的今天", icon: Stars, group: "导航", run: () => navigate("/on-this-day") },
      { id: "settings", label: "设置", icon: Settings, group: "导航", run: () => navigate("/settings") },
    ];
    const actions: Cmd[] = [
      {
        id: "toggle-theme",
        label: theme === "dark" ? "切换到浅色" : "切换到深色",
        icon: theme === "dark" ? Sun : Moon,
        group: "动作",
        run: () => setTheme(theme === "dark" ? "light" : "dark"),
      },
      {
        id: "export",
        label: "导出整库（HTML）",
        icon: Download,
        group: "动作",
        run: () => {
          exportHtml(useAppStore.getState().entries);
          setOpen(false);
        },
      },
    ];

    const dateMatch = query.match(/^(\d{4}-\d{2}-\d{2})$/);
    const dateStr = dateMatch ? dateMatch[1] ?? "" : "";
    const dateCmd: Cmd[] = dateMatch
      ? [
          {
            id: "goto-date",
            label: `打开 ${dateStr}`,
            hint: "日记",
            icon: CalendarDays,
            group: "跳转",
            run: () => openEntry(dateStr),
          },
        ]
      : [];

    const q = query.trim().toLowerCase();
    const titleCmds: Cmd[] =
      q.length > 0
        ? entries
            .filter((e) => e.title.toLowerCase().includes(q))
            .slice(0, 6)
            .map((e) => ({
              id: `entry-${e.date}`,
              label: e.title || "(无标题)",
              hint: e.date,
              icon: PenLine,
              group: "日记",
              run: () => openEntry(e.date),
            }))
        : [];

    const vaultCmds: Cmd[] = vaults.map((v) => ({
      id: `vault-${v.id}`,
      label: `切换到日记库：${v.name}`,
      hint: v.id === activeVaultId ? "当前" : undefined,
      icon: Layers,
      group: "日记库",
      run: () => {
        void switchVault(v.id);
        setOpen(false);
      },
    }));

    return [...nav, ...dateCmd, ...actions, ...titleCmds, ...vaultCmds];
  }, [query, entries, theme, vaults, activeVaultId, navigate, setActiveDate, setTheme, switchVault]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q || /^\d{4}-\d{2}-\d{2}$/.test(q)) return cmds;
    return cmds.filter(
      (c) =>
        c.label.toLowerCase().includes(q) ||
        (c.hint ?? "").toLowerCase().includes(q),
    );
  }, [cmds, query]);

  useEffect(() => {
    setActive(0);
  }, [query]);

  if (!open) return null;

  // Group while keeping a global index for keyboard navigation.
  const groups: { name: string; items: Cmd[] }[] = [];
  for (const c of filtered) {
    let g = groups.find((x) => x.name === c.group);
    if (!g) {
      g = { name: c.group, items: [] };
      groups.push(g);
    }
    g.items.push(c);
  }
  let globalIdx = -1;

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((a) => Math.min(a + 1, filtered.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((a) => Math.max(a - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      filtered[active]?.run();
    } else if (e.key === "Escape") {
      e.preventDefault();
      setOpen(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center bg-black/40 px-4 pt-[12vh] backdrop-blur-sm"
      onMouseDown={() => setOpen(false)}
    >
      <div
        className="w-full max-w-xl overflow-hidden rounded-2xl border border-border bg-card text-card-foreground shadow-2xl"
        onMouseDown={(e) => e.stopPropagation()}
      >
        <input
          autoFocus
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={onKeyDown}
          placeholder="输入命令、日期 (YYYY-MM-DD) 或日记标题…"
          className="w-full border-b border-border bg-transparent px-4 py-3 text-sm outline-none placeholder:text-muted-foreground"
        />
        <div className="max-h-[52vh] overflow-y-auto py-2">
          {filtered.length === 0 && (
            <div className="px-4 py-6 text-center text-sm text-muted-foreground">
              没有匹配项
            </div>
          )}
          {groups.map((g) => (
            <div key={g.name}>
              <div className="px-4 py-1 text-xs text-muted-foreground">{g.name}</div>
              {g.items.map((c) => {
                globalIdx += 1;
                const idx = globalIdx;
                return (
                  <button
                    key={c.id}
                    type="button"
                    onClick={() => c.run()}
                    onMouseEnter={() => setActive(idx)}
                    className={cn(
                      "flex w-full items-center gap-3 px-4 py-2 text-left text-sm transition-colors",
                      idx === active
                        ? "bg-accent text-accent-foreground"
                        : "hover:bg-muted",
                    )}
                  >
                    <c.icon className="h-4 w-4 shrink-0" />
                    <span className="flex-1 truncate">{c.label}</span>
                    {c.hint && (
                      <span className="text-xs text-muted-foreground">{c.hint}</span>
                    )}
                  </button>
                );
              })}
            </div>
          ))}
        </div>
        <div className="flex items-center justify-between border-t border-border px-4 py-2 text-xs text-muted-foreground">
          <span className="flex items-center gap-3">
            <span>↑↓ 选择</span>
            <span className="flex items-center gap-1">
              <CornerDownLeft className="h-3 w-3" /> 打开
            </span>
            <span>esc 关闭</span>
          </span>
          <span>⌘K</span>
        </div>
      </div>
    </div>
  );
}
