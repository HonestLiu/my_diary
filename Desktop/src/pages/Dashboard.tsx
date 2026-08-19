import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import {
  PenLine,
  FileText,
  Flame,
  Calendar,
  Heart,
  Sparkles,
} from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { formatHumanDate, formatDateKey } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { StatCard } from "@/components/dashboard/StatCard";
import { MoodSelector } from "@/components/dashboard/MoodSelector";
import { RecentEntries } from "@/components/dashboard/RecentEntries";
import { DistributionCard } from "@/components/dashboard/DistributionCard";
import { TagCloud } from "@/components/dashboard/TagCloud";

export default function Dashboard() {
  const navigate = useNavigate();
  const today = new Date();
  const stats = useAppStore((s) => s.stats);
  const streak = useAppStore((s) => s.streak);
  const recentEntries = useAppStore((s) => s.recentEntries);
  const entries = useAppStore((s) => s.entries);
  const startNewEntry = useAppStore((s) => s.startNewEntry);

  // Always a brand-new entry, even if today already has some.
  const startRecording = () => {
    startNewEntry(formatDateKey(today));
    navigate("/editor");
  };

  // 与移动端一致的四项统计：本月 / 连续 / 喜欢 / 总计。
  const thisMonth = formatDateKey(today).slice(0, 7);
  const monthCount = entries.filter((e) => e.date.startsWith(thisMonth)).length;
  const favCount = entries.filter((e) => e.favorite).length;

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-[1400px] px-6 py-6">
        {/* Hero */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, ease: "easeOut" }}
          className="flex flex-col gap-5 rounded-2xl border border-border bg-card p-6 shadow-soft md:flex-row md:items-center md:justify-between"
        >
          <div className="min-w-0">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Sparkles className="h-4 w-4 text-primary" />
              欢迎回来
            </div>
            <h1 className="mt-2 text-3xl font-semibold tracking-tight">
              {formatHumanDate(today)}
            </h1>
            <p className="mt-1.5 text-muted-foreground">
              记录此刻的想法，文字会替你记住生活。
            </p>
          </div>

          <div className="flex flex-col gap-3 md:items-end">
            <div className="flex items-center gap-2 self-start md:self-auto">
              <span className="text-sm text-muted-foreground">今天的心情</span>
              <MoodSelector />
            </div>
            <Button size="lg" onClick={startRecording} className="shrink-0">
              <PenLine className="h-5 w-5" />
              开始记录
            </Button>
          </div>
        </motion.div>

        {/* Stats row（与移动端一致：本月 / 连续 / 喜欢 / 总计） */}
        <div className="mt-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
          <StatCard
            icon={Calendar}
            label="本月"
            value={monthCount}
            hint="本月篇数"
            delay={0.05}
          />
          <StatCard
            icon={Flame}
            label="连续"
            value={streak}
            hint="坚持记录"
            delay={0.1}
          />
          <StatCard
            icon={Heart}
            label="喜欢"
            value={favCount}
            hint="标记喜欢"
            delay={0.15}
            accent="hsl(0 84% 60%)"
          />
          <StatCard
            icon={FileText}
            label="总计"
            value={stats.entries}
            hint="累计篇数"
            delay={0.2}
          />
        </div>

        {/* Body: recent entries (wide) + 心情/天气统计 + 标签云 (narrow) */}
        <div className="mt-6 grid grid-cols-1 gap-6 xl:grid-cols-3">
          <div className="xl:col-span-2">
            <RecentEntries entries={recentEntries} />
          </div>
          <div className="flex flex-col gap-6 xl:col-span-1">
            <DistributionCard entries={entries} />
            <TagCloud />
          </div>
        </div>
      </div>
    </div>
  );
}
