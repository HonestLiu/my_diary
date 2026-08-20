/**
 * 冲突解决对话框：点击条目卡片上的「⚠ 冲突待解决」徽章后弹出。
 * 两个按钮：保留本地 / 采用远端。调用 Rust `resolve_conflict` 命令。
 */
import { useState } from "react";
import { AlertTriangle, X } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { useAppStore } from "@/store/appStore";
import { isTauri } from "@/lib/storage/types";

export function ConflictResolveDialog() {
  const path = useAppStore((s) => s.resolveConflictPath);
  const setPath = useAppStore((s) => s.setResolveConflictPath);
  const settings = useAppStore((s) => s.settings);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!path) return null;

  const config = settings.sync;
  const vaultRoot = useAppStore.getState().repo.vaultRoot;

  const resolve = async (resolution: "local" | "remote") => {
    if (!isTauri() || !vaultRoot || !config || config.provider === "none") return;
    setBusy(true);
    setError(null);
    try {
      await invoke("resolve_conflict", {
        vaultRoot,
        config,
        path,
        resolution,
      });
      setPath(null);
      await useAppStore.getState().refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  const filename = path.split("/").pop() ?? path;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={() => !busy && setPath(null)}
    >
      <div
        className="w-full max-w-sm rounded-2xl bg-card p-6 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-amber-100">
            <AlertTriangle className="h-5 w-5 text-amber-600" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="text-base font-semibold text-foreground">
              同步冲突
            </h3>
            <p className="mt-1 truncate text-sm text-muted-foreground">
              {filename}
            </p>
            <p className="mt-2 text-sm text-muted-foreground">
              此条目在桌面端和移动端都被修改过，请选择保留哪一个版本。两侧副本已保存在
              <code className="mx-0.5 rounded bg-muted px-1 py-0.5 text-xs">
                conflicts/
              </code>
              目录。
            </p>
          </div>
          <button
            type="button"
            disabled={busy}
            onClick={() => setPath(null)}
            className="shrink-0 rounded-lg p-1 text-muted-foreground hover:bg-muted"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {error && (
          <div className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">
            {error}
          </div>
        )}

        <div className="flex gap-3">
          <button
            type="button"
            disabled={busy}
            onClick={() => void resolve("local")}
            className="flex-1 rounded-xl bg-primary px-4 py-2.5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-60"
          >
            {busy ? "处理中…" : "保留本地版本"}
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={() => void resolve("remote")}
            className="flex-1 rounded-xl border border-border px-4 py-2.5 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted disabled:opacity-60"
          >
            采用远端版本
          </button>
        </div>
      </div>
    </div>
  );
}
