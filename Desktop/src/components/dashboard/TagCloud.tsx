import { useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { Tag } from "lucide-react";
import { Card } from "@/components/ui/card";
import { useAppStore } from "@/store/appStore";

/**
 * 标签云 —— 与移动端「我的」页同款：按使用频次缩放字号与强调色浓度
 * （高频更大更深），最多展示前 15 个；点击某标签进入搜索。
 */
export function TagCloud() {
  const entries = useAppStore((s) => s.entries);
  const navigate = useNavigate();

  const { tags, total } = useMemo(() => {
    const map = new Map<string, number>();
    for (const e of entries) {
      for (const t of e.tags) map.set(t, (map.get(t) ?? 0) + 1);
    }
    return {
      tags: [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, 15),
      total: map.size,
    };
  }, [entries]);

  const maxCount = tags[0]?.[1] ?? 1;
  const primary = "hsl(var(--primary))";

  return (
    <Card className="p-5">
      <div className="flex items-center justify-between">
        <h3 className="flex items-center gap-1.5 text-base font-semibold">
          <Tag className="h-4 w-4 text-muted-foreground" />
          标签云
        </h3>
        <span className="text-xs text-muted-foreground">共 {total} 个</span>
      </div>

      <div className="mt-4 flex flex-wrap gap-2.5">
        {tags.length === 0 ? (
          <p className="py-4 text-sm leading-relaxed text-muted-foreground">
            还没有标签，写日记时给条目加标签后，会在这里按使用频次汇总成云。
          </p>
        ) : (
          tags.map(([tag, count]) => {
            const ratio = count / maxCount; // 0..1
            return (
              <button
                key={tag}
                type="button"
                title={`搜索 #${tag}`}
                onClick={() => navigate("/search", { state: { q: tag } })}
                className="rounded-full transition-transform hover:scale-105"
                style={{
                  backgroundColor: `color-mix(in srgb, ${primary} ${8 + ratio * 12}%, transparent)`,
                  color: `color-mix(in srgb, ${primary} ${55 + ratio * 45}%, transparent)`,
                  padding: "8px 13px",
                  fontSize: 11 + ratio * 4,
                  fontWeight: 600,
                }}
              >
                #{tag}
              </button>
            );
          })
        )}
      </div>
    </Card>
  );
}
