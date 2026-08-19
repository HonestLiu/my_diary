import { CloudOff, Heart, MapPin } from "lucide-react";
import type { ReactNode } from "react";
import { MoodGlyph } from "@/components/MoodGlyph";
import { WeatherGlyph } from "@/components/WeatherGlyph";
import { EntryCover } from "@/components/EntryCover";
import { cn } from "@/lib/utils";
import type { AssetRef, Mood, Weather } from "@/types/journal";

/**
 * 与移动端 EntryCard 同构的日记列表卡片：柔和投影无边框圆角卡。
 * 布局：标题行（标题 + 心情/天气 + 右侧 meta）→ 两行预览 → 底部 meta 胶囊，
 * 右侧可选 84×84 封面图。
 */
interface EntryCardProps {
  title: string;
  /** 标题行右侧的次要信息（日期等）。 */
  meta?: ReactNode;
  mood?: Mood | null;
  weather?: Weather | null;
  /** 两行预览；可为 ReactNode（如搜索高亮摘要）。 */
  preview?: ReactNode;
  location?: string;
  tags?: string[];
  /** 喜欢标记：标题行右侧红心（与移动端一致）。 */
  favorite?: boolean;
  /** 尚未同步到云端：标题行右侧显示「未同步」标识。 */
  unsynced?: boolean;
  /** 封面资产（图片优先，其次视频）；缺省不显示封面。 */
  cover?: AssetRef | null;
  onClick?: () => void;
  className?: string;
}

export function EntryCard({
  title,
  meta,
  mood,
  weather,
  preview,
  location,
  tags,
  cover,
  favorite,
  unsynced,
  onClick,
  className,
}: EntryCardProps) {
  const hasMetaChips =
    Boolean(location?.trim()) || (tags !== undefined && tags.length > 0);
  return (
    <div
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
      onClick={onClick}
      onKeyDown={
        onClick
          ? (e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                onClick();
              }
            }
          : undefined
      }
      className={cn(
        "flex items-start gap-3.5 rounded-xl bg-card px-4 py-3.5 shadow-soft transition-shadow",
        onClick &&
          "cursor-pointer hover:shadow-soft-lg focus:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        className,
      )}
    >
      <div className="min-w-0 flex-1">
        {/* 标题行：标题 + 心情/天气 矢量图标 + 右侧 meta */}
        <div className="flex items-center gap-2">
          <span className="min-w-0 truncate text-[15px] font-bold text-foreground">
            {title || "未命名"}
          </span>
          {mood && (
            <MoodGlyph mood={mood} className="shrink-0 text-base text-muted-foreground" />
          )}
          {weather && weather !== "unknown" && (
            <WeatherGlyph
              weather={weather}
              className="shrink-0 text-base text-muted-foreground"
            />
          )}
          {favorite && (
            <Heart className="h-[15px] w-[15px] shrink-0 fill-red-500 text-red-500" />
          )}
          {(unsynced || meta) && (
            <div className="ml-auto flex shrink-0 items-center gap-2">
              {unsynced && (
                <span
                  className="inline-flex items-center gap-1 rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary"
                  title="尚未同步到云端"
                >
                  <CloudOff className="h-3 w-3" />
                  未同步
                </span>
              )}
              {meta && (
                <span className="text-xs text-muted-foreground">{meta}</span>
              )}
            </div>
          )}
        </div>

        {/* 正文预览两行 */}
        {preview && (
          <p className="mt-1.5 line-clamp-2 text-[13px] text-muted-foreground">
            {preview}
          </p>
        )}

        {/* 底部 meta 胶囊：地点 + 标签 */}
        {hasMetaChips && (
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            {location?.trim() && (
              <span className="inline-flex items-center gap-1 rounded-full bg-muted px-1.5 py-0.5 text-[11px] text-muted-foreground">
                <MapPin className="h-3 w-3" />
                {location.trim()}
              </span>
            )}
            {tags?.slice(0, 2).map((t) => (
              <span
                key={t}
                className="inline-flex items-center rounded-full bg-muted px-1.5 py-0.5 text-[11px] text-muted-foreground"
              >
                #{t}
              </span>
            ))}
          </div>
        )}
      </div>

      {/* 右侧封面 84×84（与移动端一致） */}
      {cover && <EntryCover path={cover.path} kind={cover.kind} />}
    </div>
  );
}
