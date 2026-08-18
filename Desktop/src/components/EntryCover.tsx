import { useEffect, useState } from "react";
import { ImageIcon } from "lucide-react";
import { getStorage } from "@/lib/storage";
import { cn } from "@/lib/utils";

/**
 * 卡片右侧 84×84 封面图：将 vault 相对路径（assets/...）解析为可渲染 URL
 * （Tauri → data URL，浏览器 → object URL），与移动端 EntryCard 封面同款。
 * 加载中 / 解析失败时显示占位块。
 */
export function EntryCover({
  path,
  className,
}: {
  path: string;
  className?: string;
}) {
  const [url, setUrl] = useState<string>("");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    let created: string | null = null;
    getStorage()
      .resolveUrl(path)
      .then((u) => {
        if (!active) return;
        setUrl(u);
        if (u.startsWith("blob:")) created = u;
      })
      .catch(() => {
        if (active) setFailed(true);
      });
    return () => {
      active = false;
      if (created) URL.revokeObjectURL(created);
    };
  }, [path]);

  const placeholder = (
    <div
      className={cn(
        "flex h-[84px] w-[84px] shrink-0 items-center justify-center rounded-xl bg-muted",
        className,
      )}
    >
      <ImageIcon className="h-6 w-6 text-muted-foreground" />
    </div>
  );

  if (failed || !url) return placeholder;
  return (
    <img
      src={url}
      alt=""
      loading="lazy"
      onError={() => setFailed(true)}
      className={cn(
        "h-[84px] w-[84px] shrink-0 rounded-xl object-cover",
        className,
      )}
    />
  );
}
