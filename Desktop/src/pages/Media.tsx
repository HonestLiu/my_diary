import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { Layers, List, X, PenLine } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { MediaImage } from "@/components/media/MediaImage";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";

type MediaMode = "fan" | "timeline";

/** 扑克扇卡片基准尺寸（对应移动端 118×150 等比放大）。 */
const COVER_W = 170;
const COVER_H = Math.round((COVER_W * 150) / 118);
const DECK_W = COVER_W + 22;
const DECK_H = COVER_H + 16;

const WEEKDAYS = ["日", "一", "二", "三", "四", "五", "六"];

function formatPillDate(dateKey: string): string {
  const d = new Date(dateKey + "T00:00:00");
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 周${WEEKDAYS[d.getDay()]}`;
}

/**
 * 媒体画廊 —— 与移动端 MediaScreen 同款双风格：
 * - 扑克扇：按日期降序铺排，每篇含媒体的日记是一个「扑克扇」单元
 *   （封面 + 多篇时两张纯色牌背堆叠暗示 + 浮动日期胶囊 + 计数徽章）；
 * - 时间轴：左侧日期列 + 主题色圆点竖线 + 右侧卡片（标题 + 缩略图行）。
 */
export default function Media() {
  const entries = useAppStore((s) => s.entries);
  const openEntry = useAppStore((s) => s.openEntry);
  const navigate = useNavigate();

  const [mode, setMode] = useState<MediaMode>("fan");
  const [preview, setPreview] = useState<JournalEntry | null>(null);

  const mediaEntries = useMemo(
    () =>
      entries
        .filter((e) => e.assets.length > 0)
        .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0)),
    [entries],
  );
  const total = mediaEntries.reduce((s, e) => s + e.assets.length, 0);

  const openDiary = (e: JournalEntry) => {
    setPreview(null);
    openEntry(e.id, e.date);
    navigate("/editor");
  };

  return (
    <div className="h-full overflow-y-auto px-6 py-6">
      <div className="mx-auto max-w-[1400px]">
        <div className="mb-6 flex items-center justify-between gap-4">
          <h1 className="text-2xl font-semibold tracking-tight text-foreground">
            媒体
          </h1>
          <div className="flex items-center gap-3">
            {total > 0 && (
              <span className="text-sm text-muted-foreground">
                {total} 个媒体
              </span>
            )}
            {/* 模式切换（与移动端 SegmentedButton 同款胶囊） */}
            <div className="flex items-center rounded-full bg-muted p-0.5">
              <button
                type="button"
                title="扑克扇"
                onClick={() => setMode("fan")}
                className={cn(
                  "flex h-8 w-9 items-center justify-center rounded-full transition-colors",
                  mode === "fan"
                    ? "bg-card text-foreground shadow-soft"
                    : "text-muted-foreground hover:text-foreground",
                )}
              >
                <Layers className="h-4 w-4" />
              </button>
              <button
                type="button"
                title="时间轴"
                onClick={() => setMode("timeline")}
                className={cn(
                  "flex h-8 w-9 items-center justify-center rounded-full transition-colors",
                  mode === "timeline"
                    ? "bg-card text-foreground shadow-soft"
                    : "text-muted-foreground hover:text-foreground",
                )}
              >
                <List className="h-4 w-4" />
              </button>
            </div>
          </div>
        </div>

        {mediaEntries.length === 0 ? (
          <div className="flex flex-col items-center rounded-2xl border border-border bg-card p-14 text-center text-muted-foreground">
            <Layers className="mb-3 h-8 w-8 text-primary" />
            <p>还没有媒体。</p>
            <p className="mt-1 text-sm">
              给日记插入图片、音视频后，会在这里按日记汇总展示。
            </p>
          </div>
        ) : mode === "fan" ? (
          <FanView entries={mediaEntries} onOpen={setPreview} />
        ) : (
          <TimelineView entries={mediaEntries} onOpen={setPreview} />
        )}
      </div>

      {preview && (
        <PreviewModal
          entry={preview}
          onClose={() => setPreview(null)}
          onOpenDiary={openDiary}
        />
      )}
    </div>
  );
}

/** 扑克扇布局：固定尺寸卡片按 Wrap 铺排，多篇媒体时牌背右探 22 已计入。 */
function FanView({
  entries,
  onOpen,
}: {
  entries: JournalEntry[];
  onOpen: (e: JournalEntry) => void;
}) {
  return (
    <div className="flex flex-wrap gap-x-6 gap-y-8">
      {entries.map((e, i) => (
        <motion.div
          key={e.id}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: i * 0.02 }}
        >
          <FanCard entry={e} onOpen={() => onOpen(e)} />
        </motion.div>
      ))}
    </div>
  );
}

/** 单篇日记的扑克扇单元（与移动端 _EntryFan 同构）。 */
function FanCard({
  entry,
  onOpen,
}: {
  entry: JournalEntry;
  onOpen: () => void;
}) {
  const cover = entry.assets[0]!;
  const hasFan = entry.assets.length > 1;

  return (
    <button
      type="button"
      onClick={onOpen}
      className="relative block text-left"
    >
      <div
        className="relative"
        style={{ width: DECK_W, height: DECK_H }}
      >
        {/* 牌背：仅多篇媒体时做堆叠暗示，不显示图片 */}
        {hasFan && (
          <>
            <div
              className="absolute rounded-xl border border-border bg-muted/80 shadow-soft-lg"
              style={{
                width: COVER_W,
                height: COVER_H,
                transform: "translate(16px,-14px) rotate(7deg)",
                transformOrigin: "bottom left",
              }}
            />
            <div
              className="absolute rounded-xl border border-border bg-muted/80 shadow-soft"
              style={{
                width: COVER_W,
                height: COVER_H,
                transform: "translate(8px,-7px) rotate(3.5deg)",
                transformOrigin: "bottom left",
              }}
            />
          </>
        )}
        {/* 封面：锚定左下角 */}
        <div
          className="absolute bottom-0 left-0 overflow-hidden rounded-xl shadow-soft"
          style={{ width: COVER_W, height: COVER_H }}
        >
          <MediaImage asset={cover} className="h-full w-full" />
        </div>
      </div>

      {/* 日期胶囊：有扇时略高于卡片，单卡时贴边上缘 */}
      <span
        className="absolute left-1.5 rounded-full bg-card px-2.5 py-1 text-xs font-bold text-foreground shadow-lg"
        style={{ top: hasFan ? -4 : 6 }}
      >
        {formatPillDate(entry.date)}
      </span>

      {/* 多篇媒体时右下角计数徽章 */}
      {hasFan && (
        <span className="absolute -bottom-0.5 right-0 rounded-full bg-card px-2 py-0.5 text-xs font-bold text-foreground shadow-lg">
          {entry.assets.length}
        </span>
      )}
    </button>
  );
}

/** 时间轴布局：日期列 + 圆点竖线 + 内容卡片（与移动端 _TimelineItem 同构）。 */
function TimelineView({
  entries,
  onOpen,
}: {
  entries: JournalEntry[];
  onOpen: (e: JournalEntry) => void;
}) {
  return (
    <div>
      {entries.map((e, i) => (
        <TimelineItem
          key={e.id}
          entry={e}
          isLast={i === entries.length - 1}
          onOpen={() => onOpen(e)}
        />
      ))}
    </div>
  );
}

function TimelineItem({
  entry,
  isLast,
  onOpen,
}: {
  entry: JournalEntry;
  isLast: boolean;
  onOpen: () => void;
}) {
  const d = new Date(entry.date + "T00:00:00");
  const mmdd = `${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`;

  return (
    <div className="flex items-stretch">
      {/* 日期列 */}
      <div className="w-[74px] shrink-0 pt-0.5 pr-2.5 text-right">
        <div className="text-[13px] font-bold leading-[1.2] text-foreground">
          {mmdd}
        </div>
        <div className="text-xs text-muted-foreground">{d.getFullYear()}</div>
      </div>

      {/* 时间线：圆点 + 竖线（最后一条不延伸） */}
      <div className="flex w-[26px] shrink-0 flex-col items-center">
        <span className="mt-1 h-[11px] w-[11px] rounded-full bg-primary ring-2 ring-card" />
        {!isLast && <span className="w-[2px] flex-1 bg-border" />}
      </div>

      {/* 内容卡片 */}
      <div className={cn("min-w-0 flex-1", isLast ? "pb-2" : "pb-5")}>
        <button
          type="button"
          onClick={onOpen}
          className="w-full rounded-xl border border-border bg-card p-3 text-left shadow-soft transition-shadow hover:shadow-soft-lg"
        >
          <div className="flex items-center gap-2">
            <span className="min-w-0 flex-1 truncate text-[15px] font-bold text-foreground">
              {entry.title || "未命名"}
            </span>
            <span className="shrink-0 rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
              {entry.assets.length}
            </span>
          </div>
          {/* 缩略图行：最多平铺 6 张，超出收进末尾 +N */}
          <div className="mt-2.5 flex gap-1.5 overflow-x-auto">
            {entry.assets.slice(0, 6).map((a) => (
              <MediaImage
                key={a.path}
                asset={a}
                className="h-16 w-20 shrink-0 rounded-lg"
              />
            ))}
            {entry.assets.length > 6 && (
              <div className="flex h-16 w-11 shrink-0 items-center justify-center rounded-lg border border-border bg-muted text-xs font-bold text-muted-foreground">
                +{entry.assets.length - 6}
              </div>
            )}
          </div>
        </button>
      </div>
    </div>
  );
}

/** 预览弹窗：该日记全部媒体 + 「打开日记」。 */
function PreviewModal({
  entry,
  onClose,
  onOpenDiary,
}: {
  entry: JournalEntry;
  onClose: () => void;
  onOpenDiary: (e: JournalEntry) => void;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-6"
      onClick={onClose}
    >
      <div
        className="flex max-h-[85vh] w-full max-w-3xl flex-col overflow-hidden rounded-2xl bg-card shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between gap-3 border-b border-border px-5 py-3">
          <div className="min-w-0">
            <h3 className="truncate text-base font-semibold text-foreground">
              {entry.title || "未命名"}
            </h3>
            <p className="text-xs text-muted-foreground">
              {formatPillDate(entry.date)} · {entry.assets.length} 个媒体
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="overflow-y-auto p-5">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {entry.assets.map((a) => (
              <div
                key={a.path}
                className="relative aspect-square overflow-hidden rounded-xl bg-muted"
              >
                <MediaImage asset={a} className="h-full w-full" />
              </div>
            ))}
          </div>
        </div>
        <div className="flex items-center justify-end border-t border-border px-5 py-3">
          <Button variant="outline" onClick={() => onOpenDiary(entry)}>
            <PenLine className="h-4 w-4" />
            打开日记
          </Button>
        </div>
      </div>
    </div>
  );
}
