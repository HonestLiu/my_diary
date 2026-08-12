import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { History, RotateCcw, X, Clock } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { formatHumanDate } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";
import type { VersionMeta } from "@/lib/version";

interface Props {
  dateKey: string;
  onRestore: (entry: JournalEntry) => void;
  onClose: () => void;
}

/** Modal listing historical versions of the active entry, with restore. */
export function VersionHistory({ dateKey, onRestore, onClose }: Props) {
  const repo = useAppStore((s) => s.repo);
  const [versions, setVersions] = useState<VersionMeta[]>([]);
  const [restoring, setRestoring] = useState<number | null>(null);

  useEffect(() => {
    void repo.listVersions(dateKey).then(setVersions);
  }, [repo, dateKey]);

  const handleRestore = async (version: number) => {
    setRestoring(version);
    try {
      const entry = await repo.restoreVersion(dateKey, version);
      onRestore(entry);
      onClose();
    } finally {
      setRestoring(null);
    }
  };

  return (
    <AnimatePresence>
      <motion.div
        className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 backdrop-blur-sm"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        onClick={onClose}
      >
        <motion.div
          className="w-[460px] max-w-[92vw] rounded-3xl border border-border bg-card p-5 shadow-xl"
          initial={{ scale: 0.95, y: 10 }}
          animate={{ scale: 1, y: 0 }}
          exit={{ scale: 0.95, y: 10 }}
          onClick={(e) => e.stopPropagation()}
        >
          <div className="mb-4 flex items-center justify-between">
            <div className="flex items-center gap-2 text-foreground">
              <History className="h-5 w-5 text-amber-500" />
              <h2 className="text-lg font-semibold">历史版本</h2>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg p-1 text-muted-foreground hover:bg-muted"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          {versions.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              还没有历史版本。每次保存都会自动留存一个版本。
            </p>
          ) : (
            <div className="flex max-h-[50vh] flex-col gap-2 overflow-y-auto">
              {versions.map((v) => (
                <div
                  key={v.version}
                  className="rounded-2xl border border-border p-3"
                >
                  <div className="mb-1 flex items-center justify-between">
                    <span className="flex items-center gap-1.5 text-sm font-medium text-foreground">
                      <Clock className="h-3.5 w-3.5 text-muted-foreground" />
                      版本 v{v.version}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {v.updated_at
                        ? formatHumanDate(new Date(v.updated_at))
                        : ""}
                    </span>
                  </div>
                  <p className="mb-2 line-clamp-2 text-xs text-muted-foreground">
                    {v.preview || v.title}
                  </p>
                  <button
                    type="button"
                    onClick={() => handleRestore(v.version)}
                    disabled={restoring === v.version}
                    className="flex items-center gap-1.5 rounded-lg bg-foreground px-3 py-1.5 text-xs font-medium text-background hover:bg-foreground/90 disabled:opacity-60"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                    {restoring === v.version ? "恢复中…" : "恢复到此版本"}
                  </button>
                </div>
              ))}
            </div>
          )}
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
