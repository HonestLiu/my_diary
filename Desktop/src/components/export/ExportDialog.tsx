import { useCallback, useEffect, useState } from "react";
import { CheckCircle2, AlertTriangle, Download, X, FileText, FolderArchive, Loader2 } from "lucide-react";
import { exportHtml, exportZip, type ExportFormat, type ExportResult } from "@/lib/export";
import { useAppStore } from "@/store/appStore";
import { cn } from "@/lib/utils";

interface ExportDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

type Phase = "pick" | "exporting" | "done" | "error";

const FORMATS: { id: ExportFormat; label: string; desc: string; icon: typeof FileText }[] = [
  {
    id: "html",
    label: "单个 HTML",
    desc: "一本可离线阅读的日记书，图片直接嵌入文件内。",
    icon: FileText,
  },
  {
    id: "zip",
    label: "Markdown 压缩包 (.zip)",
    desc: "一篇一文件，含全部图片与附件，任何编辑器可打开。",
    icon: FolderArchive,
  },
];

export function ExportDialog({ open, onOpenChange }: ExportDialogProps) {
  const entries = useAppStore((s) => s.entries);
  const storageAdapter = useAppStore((s) => s.repo.storageAdapter);

  const [format, setFormat] = useState<ExportFormat>("html");
  const [phase, setPhase] = useState<Phase>("pick");
  const [progress, setProgress] = useState(0);
  const [result, setResult] = useState<ExportResult | null>(null);

  useEffect(() => {
    if (open) {
      setFormat("html");
      setPhase("pick");
      setProgress(0);
      setResult(null);
    }
  }, [open]);

  const close = useCallback(() => {
    if (phase === "exporting") return;
    setResult(null);
    setPhase("pick");
    setProgress(0);
    onOpenChange(false);
  }, [phase, onOpenChange]);

  const run = async () => {
    setPhase("exporting");
    setProgress(0);
    const res =
      format === "html"
        ? await exportHtml(entries, storageAdapter, setProgress)
        : await exportZip(entries, storageAdapter, setProgress);
    setResult(res);
    if (res.ok) setPhase("done");
    else if (res.cancelled) {
      setPhase("pick");
      onOpenChange(false);
    } else setPhase("error");
  };

  if (!open) return null;

  const count = entries.length;
  const ActiveIcon = FORMATS.find((f) => f.id === format)?.icon ?? FileText;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4 backdrop-blur-sm"
      onMouseDown={close}
    >
      <div
        className="w-full max-w-md overflow-hidden rounded-2xl border border-border bg-card text-card-foreground shadow-2xl"
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <h2 className="flex items-center gap-2 text-sm font-semibold">
            <Download className="h-4 w-4" />
            导出日记
          </h2>
          {phase !== "exporting" && (
            <button
              type="button"
              onClick={close}
              aria-label="关闭"
              className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>

        <div className="px-5 py-4">
          {phase === "pick" && (
            <>
              <p className="mb-4 text-sm text-muted-foreground">
                共 {count} 篇日记。导出后可用任何文本编辑器或笔记软件打开，远离锁定格式。
              </p>
              <div className="space-y-2">
                {FORMATS.map((f) => (
                  <button
                    key={f.id}
                    type="button"
                    onClick={() => setFormat(f.id)}
                    className={cn(
                      "flex w-full items-start gap-3 rounded-xl border p-3 text-left transition",
                      format === f.id
                        ? "border-primary bg-accent"
                        : "border-border hover:bg-muted",
                    )}
                  >
                    <f.icon
                      className={cn(
                        "mt-0.5 h-5 w-5 shrink-0",
                        format === f.id ? "text-primary" : "text-muted-foreground",
                      )}
                    />
                    <span>
                      <span className="block text-sm font-medium">{f.label}</span>
                      <span className="block text-xs text-muted-foreground">{f.desc}</span>
                    </span>
                  </button>
                ))}
              </div>
            </>
          )}

          {phase === "exporting" && (
            <div className="py-2">
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Loader2 className="h-4 w-4 animate-spin" />
                正在导出{count} 篇日记…
              </div>
              <div className="mt-4 h-2 w-full overflow-hidden rounded-full bg-muted">
                <div
                  className="h-full rounded-full bg-primary transition-all duration-200"
                  style={{ width: `${progress}%` }}
                />
              </div>
              <p className="mt-2 text-right text-xs tabular-nums text-muted-foreground">
                {progress}%
              </p>
            </div>
          )}

          {phase === "done" && result?.ok && (
            <div className="flex items-start gap-3">
              <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-green-600" />
              <div className="min-w-0 text-sm">
                <p className="font-medium text-green-700">导出完成</p>
                <p className="mt-1 break-all text-muted-foreground">
                  {result.path ? `已保存到：${result.path}` : "文件已开始下载，请查看浏览器下载内容。"}
                </p>
              </div>
            </div>
          )}

          {phase === "error" && result && "message" in result && (
            <div className="flex items-start gap-3">
              <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-red-500" />
              <div className="min-w-0 text-sm">
                <p className="font-medium text-red-600">导出失败</p>
                <p className="mt-1 break-all text-muted-foreground">
                  {result.cancelled ? "已取消导出。" : result.message ?? "未知错误"}
                </p>
              </div>
            </div>
          )}
        </div>

        <div className="flex items-center justify-end gap-2 border-t border-border px-5 py-3">
          {phase === "pick" && (
            <button
              type="button"
              onClick={close}
              className="rounded-xl border border-border px-4 py-2 text-sm text-muted-foreground transition hover:bg-muted"
            >
              取消
            </button>
          )}
          {phase === "pick" && (
            <button
              type="button"
              onClick={run}
              disabled={count === 0}
              className="flex items-center gap-2 rounded-xl bg-foreground px-4 py-2 text-sm font-medium text-background transition hover:bg-foreground/90 disabled:opacity-50"
            >
              <ActiveIcon className="h-4 w-4" />
              开始导出
            </button>
          )}
          {(phase === "done" || phase === "error") && (
            <button
              type="button"
              onClick={close}
              className="rounded-xl border border-border px-4 py-2 text-sm text-muted-foreground transition hover:bg-muted"
            >
              关闭
            </button>
          )}
        </div>
      </div>
    </div>
  );
}