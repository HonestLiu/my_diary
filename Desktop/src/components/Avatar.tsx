import { useEffect, useState } from "react";
import { getStorage } from "@/lib/storage";
import { cn } from "@/lib/utils";

/**
 * 头像：读取 settings.avatar（vault 相对路径，如 profile/avatar.png）并渲染；
 * 未设置 / 加载失败时回退为首字圆标。与移动端个人主页头像一致。
 */
export function Avatar({
  avatar,
  name,
  size = 32,
  className,
}: {
  /** settings.avatar 值；空 = 未设置。 */
  avatar: string;
  /** 回退时的首字来源（昵称）。 */
  name: string;
  size?: number;
  className?: string;
}) {
  const [url, setUrl] = useState("");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    let created: string | null = null;
    setFailed(false);
    setUrl("");
    if (!avatar.trim()) return () => undefined;
    getStorage()
      .resolveUrl(avatar)
      .then((u) => {
        if (!active) return;
        if (!u) {
          setFailed(true);
          return;
        }
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
  }, [avatar]);

  const fallback = (
    <div
      className={cn(
        "flex shrink-0 items-center justify-center rounded-full bg-primary font-semibold text-primary-foreground",
        className,
      )}
      style={{ width: size, height: size, fontSize: size * 0.44 }}
    >
      {name ? Array.from(name)[0] : "我"}
    </div>
  );

  if (!avatar.trim() || failed || !url) return fallback;
  return (
    <img
      src={url}
      alt=""
      onError={() => setFailed(true)}
      className={cn(
        "shrink-0 rounded-full object-cover",
        className,
      )}
      style={{ width: size, height: size }}
    />
  );
}
