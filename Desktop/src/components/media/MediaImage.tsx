import { useEffect, useState } from "react";
import { FileText, Image as ImageIcon, Music, Play } from "lucide-react";
import { getStorage } from "@/lib/storage";
import { cn } from "@/lib/utils";
import type { AssetRef } from "@/types/journal";

/**
 * 媒体缩略图：图片经 StorageAdapter.resolveUrl 解析为可渲染 URL
 * （Tauri → data URL，浏览器 → object URL，后者卸载时回收）；
 * 视频 / 音频 / 附件显示对应占位图标（视频带播放角标）。
 */
export function MediaImage({
  asset,
  className,
}: {
  asset: AssetRef;
  className?: string;
}) {
  const [url, setUrl] = useState("");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    let created: string | null = null;
    if (asset.kind !== "image") return;
    getStorage()
      .resolveUrl(asset.path)
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
  }, [asset]);

  const placeholder = (
    <div
      className={cn(
        "relative flex items-center justify-center bg-muted text-muted-foreground",
        className,
      )}
    >
      {asset.kind === "video" && <Play className="h-4 w-4 fill-current" />}
      {asset.kind === "audio" && <Music className="h-5 w-5" />}
      {asset.kind === "attachment" && <FileText className="h-5 w-5" />}
      {asset.kind === "image" && <ImageIcon className="h-5 w-5" />}
    </div>
  );

  if (asset.kind !== "image" || failed || !url) return placeholder;
  return (
    <img
      src={url}
      alt={asset.name ?? ""}
      loading="lazy"
      onError={() => setFailed(true)}
      className={cn("object-cover", className)}
    />
  );
}
