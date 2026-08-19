import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Sparkles, Dice5, Play } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { getStorage } from "@/lib/storage";
import { MarkdownPreview } from "@/components/MarkdownPreview";
import { Button } from "@/components/ui/button";
import type { AssetRef, JournalEntry } from "@/types/journal";

/**
 * 回忆 —— 与移动端「回忆」区块同风格，但用桌面宽屏铺成记忆墙：
 * 有图日记以封面为底（暗渐变 + 白字），无图日记用品牌色淡染文字卡（水印「忆」），
 * 角标区分「往年的今天」与「久远回忆」。数据与移动端一致：
 * 往年的今天优先，再用 2 个月之前的随机日记补足，合计 ≤ 10。
 */
export default function OnThisDay() {
  const entries = useAppStore((s) => s.entries);
  const openEntry = useAppStore((s) => s.openEntry);
  const navigate = useNavigate();

  const memories = useMemo(() => buildMemories(entries), [entries]);

  const open = (entry: JournalEntry) => {
    openEntry(entry.id, entry.date);
    navigate("/editor");
  };

  const random = () => {
    const e = entries[Math.floor(Math.random() * entries.length)];
    if (e) open(e);
  };

  return (
    <div className="h-full overflow-y-auto px-6 py-6">
      <div className="mx-auto max-w-[1500px]">
        {/* 页头 */}
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <Sparkles className="h-5 w-5 text-primary" />
              <h1 className="text-2xl font-semibold tracking-tight text-foreground">
                回忆
              </h1>
            </div>
            <p className="mt-1 text-muted-foreground">
              往年的今天 · 还有那些值得回味的旧时光
            </p>
          </div>
          <Button variant="outline" onClick={random} className="shrink-0">
            <Dice5 className="h-4 w-4" />
            随机回顾
          </Button>
        </div>

        {memories.length === 0 ? (
          <div className="mt-8 flex flex-col items-center rounded-2xl border border-border bg-card p-12 text-center">
            <div className="relative">
              <span className="text-4xl">✨</span>
            </div>
            <p className="mt-4 text-base font-medium text-foreground">
              还没有回忆
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              写下第一篇日记，未来的你会在这里遇见此刻。
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
            {memories.map((m, i) => (
              <MemoryCard
                key={m.entry.id}
                item={m}
                delay={i * 0.03}
                onOpen={() => open(m.entry)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* 数据                                                               */
/* ------------------------------------------------------------------ */

interface MemoryItem {
  entry: JournalEntry;
  /** 角标文案，如「往年的今天 · 2023」「2024年2月」。 */
  badge: string;
  /** 'onThisDay' | 'recent' */
  kind: "onThisDay" | "recent";
}

/** 计算回忆卡片数据：往年的今天优先，再用「2 个月之前（含更早）」的随机补足，合计 ≤ 10。 */
function buildMemories(entries: JournalEntry[]): MemoryItem[] {
  const now = new Date();
  const todayMd = md(now);

  // ① 往年的今天：月日相同、且年份早于今年。
  const onThisDay: MemoryItem[] = [];
  const onThisDayIds = new Set<string>();
  for (const e of entries) {
    const d = tryParse(e.date);
    if (!d || d.getFullYear() >= now.getFullYear()) continue;
    if (md(d) !== todayMd) continue;
    onThisDay.push({
      entry: e,
      badge: `往年的今天 · ${d.getFullYear()}`,
      kind: "onThisDay",
    });
    onThisDayIds.add(e.id);
  }

  // ② 2 个月之前：日期早于 (now - 2 个月) 的全部日记，随机抽补。
  const cutoff = new Date(now.getFullYear(), now.getMonth() - 2, now.getDate());
  const recent = entries.filter((e) => {
    if (onThisDayIds.has(e.id)) return false;
    const d = tryParse(e.date);
    if (!d) return false;
    return d.getTime() < cutoff.getTime();
  });
  // 以「当天」为种子随机打乱：同一天内稳定，跨天自然变化。
  shuffle(recent, now.getFullYear() * 372 + now.getMonth() * 31 + now.getDate());

  const items = [...onThisDay];
  for (const e of recent) {
    if (items.length >= 10) break;
    const d = tryParse(e.date);
    items.push({
      entry: e,
      badge: !d
        ? "回忆"
        : d.getFullYear() === now.getFullYear()
          ? `${d.getMonth() + 1}月`
          : `${d.getFullYear()}年${d.getMonth() + 1}月`,
      kind: "recent",
    });
  }
  return items.slice(0, 10);
}

function tryParse(dateKey: string): Date | null {
  const d = new Date(dateKey + "T00:00:00");
  return Number.isNaN(d.getTime()) ? null : d;
}

/** 月日 key，如 "08-19"。 */
function md(d: Date): string {
  return `${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`;
}

/** 日期角标：如「8月19日 · 星期二」。 */
function memoDate(dateKey: string): string {
  const d = tryParse(dateKey);
  if (!d) return "";
  const weekdays = ["日", "一", "二", "三", "四", "五", "六"];
  return `${d.getMonth() + 1}月${d.getDate()}日 · 星期${weekdays[d.getDay()]}`;
}

/** 当日种子随机打乱（原地）。 */
function shuffle<T>(arr: T[], seed: number): void {
  let s = seed >>> 0;
  const rand = () => {
    // xorshift32
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return (s >>> 0) / 0xffffffff;
  };
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [arr[i], arr[j]] = [arr[j]!, arr[i]!];
  }
}

/* ------------------------------------------------------------------ */
/* 卡片 UI                                                             */
/* ------------------------------------------------------------------ */

function MemoryCard({
  item,
  delay,
  onOpen,
}: {
  item: MemoryItem;
  delay: number;
  onOpen: () => void;
}) {
  const { entry } = item;
  const cover = firstCover(entry.assets);
  const hasPreview = entry.body.trim().length > 0;

  return (
    <button
      type="button"
      onClick={onOpen}
      className="group relative aspect-[4/5] w-full cursor-pointer overflow-hidden rounded-2xl border border-border text-left shadow-soft transition-all hover:-translate-y-0.5 hover:shadow-soft-lg"
      style={{ animation: `memoryIn 0.35s ease-out both`, animationDelay: `${delay}s` }}
    >
      {cover ? (
        <ImageCard
          cover={cover}
          badge={item.badge}
          dateStr={memoDate(entry.date)}
          title={entry.title || "未命名"}
          preview={hasPreview ? <MarkdownPreview body={entry.body} /> : undefined}
        />
      ) : (
        <TextCard
          badge={item.badge}
          dateStr={memoDate(entry.date)}
          title={entry.title || "未命名"}
          preview={hasPreview ? <MarkdownPreview body={entry.body} /> : undefined}
        />
      )}
    </button>
  );
}

/** 有图卡：封面作底 + 底部暗渐变保证文字可读。 */
function ImageCard({
  cover,
  badge,
  dateStr,
  title,
  preview,
}: {
  cover: AssetRef;
  badge: string;
  dateStr: string;
  title: string;
  preview?: React.ReactNode;
}) {
  return (
    <>
      <CoverImage cover={cover} />
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/75 via-black/15 to-transparent" />
      <div className="absolute left-2.5 top-2.5">
        <Badge text={badge} dark />
      </div>
      {cover.kind === "video" && (
        <div className="absolute left-1/2 top-1/2 flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-black/50 text-white">
          <Play className="ml-0.5 h-5 w-5 fill-current" />
        </div>
      )}
      <div className="absolute inset-x-2.5 bottom-2.5">
        <p className="text-[11px] font-semibold text-white/70">{dateStr}</p>
        <p className="mt-0.5 truncate text-sm font-bold text-white">
          {title}
        </p>
        {preview && (
          <p className="mt-0.5 line-clamp-2 text-xs text-white/70">{preview}</p>
        )}
      </div>
    </>
  );
}

/** 无图文字卡：品牌色淡染底 + 大号水印「忆」。 */
function TextCard({
  badge,
  dateStr,
  title,
  preview,
}: {
  badge: string;
  dateStr: string;
  title: string;
  preview?: React.ReactNode;
}) {
  return (
    <div className="absolute inset-0 overflow-hidden bg-gradient-to-br from-muted via-muted to-primary/20">
      <span className="pointer-events-none absolute -right-2 -top-4 select-none text-[96px] font-bold leading-none text-primary/15">
        忆
      </span>
      <div className="flex h-full flex-col p-3.5">
        <div>
          <Badge text={badge} />
        </div>
        <div className="mt-auto">
          <p className="text-[11px] font-semibold text-muted-foreground">
            {dateStr}
          </p>
          <p className="mt-0.5 line-clamp-2 text-sm font-bold text-foreground">
            {title}
          </p>
          {preview && (
            <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">
              {preview}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

/** 回忆角标：sparkle 图标 + 文案。 */
function Badge({ text, dark }: { text: string; dark?: boolean }) {
  return (
    <span
      className={`inline-flex max-w-full items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold ${
        dark
          ? "bg-black/35 text-white"
          : "bg-card/90 text-primary shadow-sm"
      }`}
    >
      <Sparkles className="h-3 w-3 shrink-0" />
      <span className="truncate">{text}</span>
    </span>
  );
}

/** 封面缩略图：解析 vault 相对路径为可渲染 URL。 */
function CoverImage({ cover }: { cover: AssetRef }) {
  const [url, setUrl] = useState("");

  useEffect(() => {
    let active = true;
    getStorage()
      .resolveUrl(cover.path)
      .then((u) => {
        if (active) setUrl(u);
      })
      .catch(() => undefined);
    return () => {
      active = false;
    };
  }, [cover.path]);

  if (!url) {
    return <div className="absolute inset-0 bg-muted" />;
  }
  return (
    <img
      src={url}
      alt=""
      loading="lazy"
      className="absolute inset-0 h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
    />
  );
}

/** 取首张封面：优先图片，其次视频。 */
function firstCover(assets: AssetRef[]): AssetRef | null {
  return (
    assets.find((a) => a.kind === "image") ??
    assets.find((a) => a.kind === "video") ??
    null
  );
}
