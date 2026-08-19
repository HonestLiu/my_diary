import { useEffect, useState } from "react";
import { ImageIcon, Play } from "lucide-react";
import { getStorage } from "@/lib/storage";
import { thumbnailPath } from "@/lib/vault";
import { cn } from "@/lib/utils";
import type { AssetKind } from "@/types/journal";

/**
 * 卡片封面图：优先加载 vault `assets/thumbnails/` 下的 256px 列表缩略图
 * （解码极快），不存在时回退到原资产路径。图片与视频封面均可展示
 * （视频带播放角标）。与移动端 resolveThumb 行为一致。
 */
export function EntryCover({
  path,
  kind,
  className,
}: {
  /** 资产 vault 相对路径（assets/...）。 */
  path: string;
  /** 资产类型：video 时叠加播放角标。 */
  kind?: AssetKind;
  className?: string;
}) {
  const [url, setUrl] = useState("");
  const [failed, setFailed] = useState(false);
  const isVideo = kind === "video";

  useEffect(() => {
    let active = true;
    let created: string | null = null;
    setFailed(false);
    setUrl("");

    const useUrl = (u: string) => {
      if (!active) return;
      if (!u) {
        setFailed(true);
        return;
      }
      setUrl(u);
      if (u.startsWith("blob:")) created = u;
    };

    // 优先缩略图；失败/不存在则回退原资产。
    getStorage()
      .resolveUrl(thumbnailPath(path))
      .then((u) => {
        if (!active) return;
        if (u) {
          useUrl(u);
        } else {
          return getStorage().resolveUrl(path).then(useUrl);
        }
      })
      .catch(() => {
        getStorage().resolveUrl(path).then(useUrl).catch(() => {
          if (active) setFailed(true);
        });
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
      {isVideo ? (
        <Play className="h-6 w-6 text-muted-foreground" />
      ) : (
        <ImageIcon className="h-6 w-6 text-muted-foreground" />
      )}
    </div>
  );

  if (failed || !url) return placeholder;
  return (
    <div className={cn("relative shrink-0", className)}>
      <img
        src={url}
        alt=""
        loading="lazy"
        onError={() => setFailed(true)}
        className="h-[84px] w-[84px] rounded-xl object-cover"
      />
      {isVideo && (
        <span className="absolute bottom-1 right-1 flex h-5 w-5 items-center justify-center rounded-full bg-black/60 text-white">
          <Play className="h-3 w-3 fill-current" />
        </span>
      )}
    </div>
  );
}
