import { useEffect, useState } from "react";
import { FileText, Image as ImageIcon, Music, Play } from "lucide-react";
import { getStorage } from "@/lib/storage";
import { thumbnailPath } from "@/lib/vault";
import { cn } from "@/lib/utils";
import type { AssetRef } from "@/types/journal";

/**
 * 媒体缩略图：图片与视频均优先加载 `assets/thumbnails/` 下的 256px 缩略图
 * （解码极快），不存在时回退原资产（Tauri → data URL，浏览器 → object URL，
 * 后者卸载时回收）。音频 / 附件显示对应占位图标（视频有封面时叠加播放角标）。
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
    setFailed(false);
    setUrl("");
    if (asset.kind !== "image" && asset.kind !== "video") return;

    const useUrl = (u: string) => {
      if (!active) return;
      if (!u) {
        setFailed(true);
        return;
      }
      setUrl(u);
      if (u.startsWith("blob:")) created = u;
    };

    getStorage()
      .resolveUrl(thumbnailPath(asset.path))
      .then((u) => {
        if (!active) return;
        if (u) useUrl(u);
        else return getStorage().resolveUrl(asset.path).then(useUrl);
      })
      .catch(() => {
        getStorage()
          .resolveUrl(asset.path)
          .then(useUrl)
          .catch(() => {
            if (active) setFailed(true);
          });
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

  const showable = asset.kind === "image" || asset.kind === "video";
  if (!showable || failed || !url) return placeholder;
  return (
    <div className={cn("relative", className)}>
      <img
        src={url}
        alt={asset.name ?? ""}
        loading="lazy"
        onError={() => setFailed(true)}
        className="h-full w-full object-cover"
      />
      {asset.kind === "video" && (
        <span className="absolute right-1.5 bottom-1.5 flex h-6 w-6 items-center justify-center rounded-full bg-black/60 text-white">
          <Play className="h-3.5 w-3.5 fill-current" />
        </span>
      )}
    </div>
  );
}
