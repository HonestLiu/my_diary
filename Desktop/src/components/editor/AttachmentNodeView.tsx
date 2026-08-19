import { NodeViewWrapper, type NodeViewProps } from "@tiptap/react";
import { useEffect, useRef, useState } from "react";
import {
  FileText,
  Film,
  Loader2,
  Paperclip,
  Pause,
  Play,
} from "lucide-react";
import { getStorage } from "@/lib/storage";
import { useMediaProgress } from "@/lib/editor/mediaProgress";
import type { AssetKind } from "@/types/journal";

/**
 * Renders non-image attachments (video / audio / generic file).
 *
 * Layout is purpose-built per kind so space is used well:
 *   - video  → full-width inline player + a slim meta bar underneath
 *   - audio  → compact custom player: play/pause button, filename, scrubber,
 *              elapsed / duration (replaces the bulky native controls)
 *   - file   → icon + name + size + download link
 *
 * Video and audio cards can be freely resized: when selected, a handle appears
 * at the bottom-right corner — drag it to set the card width (height follows
 * proportionally for video), double-click the handle to restore full width.
 * The chosen width persists as `data-width` on the serialized `<attachment>`
 * tag. The `src` attribute is a vault-relative path resolved through the
 * StorageAdapter.
 */
const MIN_WIDTH = 240;

export function AttachmentNodeView({
  node,
  selected,
  updateAttributes,
}: NodeViewProps) {
  const src: string = node.attrs.src ?? "";
  const name: string = node.attrs.name ?? src.split("/").pop() ?? "file";
  const kind: AssetKind = node.attrs.kind ?? "attachment";
  const size: number = Number(node.attrs.size ?? 0);
  const width: number | null = node.attrs.width ?? null;
  const [url, setUrl] = useState<string>("");
  const wrapRef = useRef<HTMLDivElement>(null);
  // 视频压缩进度（jobId = 资产相对路径 = node.src）。压缩中/完成前显示进度卡。
  const progress = kind === "video" ? useMediaProgress(src) : undefined;
  const compressing =
    progress !== undefined &&
    (progress.stage === "downloading" ||
      progress.stage === "transcoding" ||
      progress.stage === "thumbnail");

  useEffect(() => {
    let active = true;
    let created: string | null = null;
    getStorage()
      .resolveUrl(src)
      .then((u) => {
        if (!active) return;
        setUrl(u);
        if (u.startsWith("blob:")) created = u;
      })
      .catch(() => undefined);
    return () => {
      active = false;
      if (created) URL.revokeObjectURL(created);
    };
  }, [src]);

  const startResize = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    // In auto (full-width) mode, base the drag on the rendered width.
    const startW = width ?? wrapRef.current?.clientWidth ?? 640;
    const startX = e.clientX;

    const onMove = (ev: MouseEvent) => {
      const next = Math.max(
        MIN_WIDTH,
        Math.round(startW + (ev.clientX - startX)),
      );
      updateAttributes({ width: next });
    };
    const onUp = () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
    };

    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    document.body.style.cursor = "ew-resize";
    document.body.style.userSelect = "none";
  };

  const resetWidth = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    updateAttributes({ width: null });
  };

  const ring = selected ? "ring-2 ring-primary" : "";
  const handle =
    selected && kind !== "attachment" ? (
      <div
        role="slider"
        aria-label="调整卡片宽度"
        aria-valuemin={MIN_WIDTH}
        aria-valuemax={2000}
        aria-valuenow={width ?? Math.round(wrapRef.current?.clientWidth ?? 0)}
        onMouseDown={startResize}
        onDoubleClick={resetWidth}
        title="拖动调整宽度 · 双击恢复全宽"
        className="absolute -bottom-2 -right-2 z-10 h-4 w-4 cursor-ew-resize rounded-full border-2 border-background bg-primary shadow-md"
      />
    ) : null;

  const wrapStyle: React.CSSProperties | undefined = width
    ? { width: `${width}px`, maxWidth: "100%" }
    : undefined;

  if (kind === "video") {
    return (
      <NodeViewWrapper className="my-3">
        <div
          ref={wrapRef}
          className={`relative ${width ? "mx-auto" : ""}`}
          style={wrapStyle}
        >
          <div
            className={`overflow-hidden rounded-2xl border border-border bg-card/70 shadow-sm backdrop-blur ${ring}`}
          >
            {compressing ? (
              /* 压缩中卡片：进度条 + 阶段文案，完成后自动转为下方视频播放器。 */
              <div className="flex flex-col items-center gap-3 px-6 py-8">
                <div className="flex h-12 w-12 items-center justify-center rounded-full bg-accent text-primary">
                  <Loader2 className="h-6 w-6 animate-spin" />
                </div>
                <div className="w-full max-w-sm">
                  <div className="flex items-center justify-between text-sm">
                    <span className="truncate text-foreground">{name}</span>
                    <span className="ml-3 shrink-0 tabular-nums text-muted-foreground">
                      {progress?.percent ?? 0}%
                    </span>
                  </div>
                  <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-muted">
                    <div
                      className="h-full rounded-full bg-primary transition-all duration-200"
                      style={{ width: `${progress?.percent ?? 0}%` }}
                    />
                  </div>
                  <p className="mt-2 text-xs text-muted-foreground">
                    {progress?.message ?? "正在处理…"}
                  </p>
                </div>
              </div>
            ) : (
              <>
                {url && (
                  <video
                    src={url}
                    controls
                    preload="metadata"
                    className="block w-full bg-black/5"
                  />
                )}
                <div className="flex items-center gap-2 px-3 py-2">
                  <Film className="h-4 w-4 shrink-0 text-muted-foreground" />
                  <span className="truncate text-sm font-medium text-foreground">
                    {name}
                  </span>
                  <span className="ml-auto shrink-0 text-xs tabular-nums text-muted-foreground">
                    {fmtSize(size)}
                  </span>
                </div>
                {progress?.stage === "error" && (
                  <p className="border-t border-border px-3 py-1.5 text-xs text-red-500">
                    压缩失败，已保留原文件
                  </p>
                )}
              </>
            )}
          </div>
          {handle}
        </div>
      </NodeViewWrapper>
    );
  }

  if (kind === "audio") {
    return (
      <NodeViewWrapper className="my-3">
        <div
          ref={wrapRef}
          className={`relative ${width ? "mx-auto" : ""}`}
          style={wrapStyle}
        >
          {url && (
            <AudioPlayer src={url} name={name} size={size} ring={ring} />
          )}
          {handle}
        </div>
      </NodeViewWrapper>
    );
  }

  // Generic file — icon card with a download action.
  const Icon =
    name.match(/\.pdf$/i) ? FileText : Paperclip;
  return (
    <NodeViewWrapper className="my-3">
      <div
        className={`flex items-center gap-3 rounded-2xl border border-border bg-card/70 p-3 shadow-sm backdrop-blur ${ring}`}
      >
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-accent text-primary">
          <Icon className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-foreground">{name}</p>
          <p className="text-xs text-muted-foreground">{fmtSize(size)}</p>
        </div>
        {url && (
          <a
            href={url}
            download={name}
            className="shrink-0 rounded-lg border border-border px-3 py-1.5 text-sm font-medium text-primary transition hover:bg-accent"
          >
            下载
          </a>
        )}
      </div>
    </NodeViewWrapper>
  );
}

/** Compact inline audio player — play button, filename, scrubber, time. */
function AudioPlayer({
  src,
  name,
  size,
  ring,
}: {
  src: string;
  name: string;
  size: number;
  ring: string;
}) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [current, setCurrent] = useState(0);
  const [duration, setDuration] = useState(0);

  const toggle = () => {
    const a = audioRef.current;
    if (!a) return;
    if (a.paused) {
      void a.play().then(() => setPlaying(true)).catch(() => undefined);
    } else {
      a.pause();
      setPlaying(false);
    }
  };

  const seek = (e: React.ChangeEvent<HTMLInputElement>) => {
    const a = audioRef.current;
    if (!a) return;
    const t = Number(e.target.value);
    a.currentTime = t;
    setCurrent(t);
  };

  return (
    <div
      className={`flex items-center gap-3 rounded-2xl border border-border bg-card/70 p-3 shadow-sm backdrop-blur ${ring}`}
    >
      <audio
        ref={audioRef}
        src={src}
        preload="metadata"
        onTimeUpdate={(e) => setCurrent(e.currentTarget.currentTime)}
        onLoadedMetadata={(e) => setDuration(e.currentTarget.duration || 0)}
        onEnded={() => setPlaying(false)}
      />
      <button
        type="button"
        onClick={toggle}
        aria-label={playing ? "暂停" : "播放"}
        title={playing ? "暂停" : "播放"}
        className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-sm transition hover:opacity-90"
      >
        {playing ? (
          <Pause className="h-5 w-5 fill-current" />
        ) : (
          <Play className="ml-0.5 h-5 w-5 fill-current" />
        )}
      </button>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-foreground">{name}</p>
        <div className="mt-1.5 flex items-center gap-2">
          <input
            type="range"
            min={0}
            max={duration || 1}
            step={0.1}
            value={Math.min(current, duration || 0)}
            onChange={seek}
            aria-label="播放进度"
            className="h-1.5 min-w-0 flex-1 cursor-pointer accent-primary"
          />
          <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
            {fmtTime(current)} / {fmtTime(duration)}
          </span>
        </div>
      </div>
      <span className="hidden shrink-0 text-xs tabular-nums text-muted-foreground sm:inline">
        {fmtSize(size)}
      </span>
    </div>
  );
}

function fmtTime(s: number): string {
  if (!Number.isFinite(s) || s <= 0) return "0:00";
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60);
  return `${m}:${String(sec).padStart(2, "0")}`;
}

function fmtSize(bytes: number): string {
  if (bytes >= 1 << 20) return `${(bytes / (1 << 20)).toFixed(1)} MB`;
  if (bytes >= 1 << 10) return `${(bytes / (1 << 10)).toFixed(0)} KB`;
  return `${bytes} B`;
}
