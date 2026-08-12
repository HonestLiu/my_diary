import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import {
  PenLine,
  FileText,
  Type,
  Image as ImageIcon,
  Flame,
  Sparkles,
} from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { formatHumanDate, formatDateKey } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { StatCard } from "@/components/dashboard/StatCard";
import { MoodSelector } from "@/components/dashboard/MoodSelector";
import { RecentEntries } from "@/components/dashboard/RecentEntries";
import { MoodTrend } from "@/components/dashboard/MoodTrend";

export default function Dashboard() {
  const navigate = useNavigate();
  const today = new Date();
  const stats = useAppStore((s) => s.stats);
  const streak = useAppStore((s) => s.streak);
  const recentEntries = useAppStore((s) => s.recentEntries);
  const setActiveDate = useAppStore((s) => s.setActiveDate);

  const startRecording = () => {
    const key = formatDateKey(today);
    setActiveDate(key);
    navigate(`/editor?date=${key}`);
  };

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-5xl px-8 py-10">
        {/* Hero */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, ease: "easeOut" }}
          className="flex flex-col gap-6"
        >
          <div>
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Sparkles className="h-4 w-4 text-primary" />
              欢迎回来
            </div>
            <h1 className="mt-2 text-4xl font-semibold tracking-tight">
              {formatHumanDate(today)}
            </h1>
            <p className="mt-2 text-muted-foreground">
              记录此刻的想法，文字会替你记住生活。
            </p>
          </div>

          {/* Mood + CTA row */}
          <div className="flex flex-col gap-4 rounded-2xl border border-border bg-card p-6 shadow-soft sm:flex-row sm:items-center sm:justify-between">
            <div>
              <div className="mb-2 text-sm font-medium text-muted-foreground">
                今天的心情
              </div>
              <MoodSelector />
            </div>
            <Button size="lg" onClick={startRecording} className="shrink-0">
              <PenLine className="h-5 w-5" />
              开始记录
            </Button>
          </div>
        </motion.div>

        {/* Stats */}
        <div className="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatCard
            icon={FileText}
            label="日记"
            value={stats.entries}
            hint="累计篇数"
            delay={0.05}
          />
          <StatCard
            icon={Type}
            label="字数"
            value={stats.words.toLocaleString()}
            hint="累计字数"
            delay={0.1}
            accent="hsl(200 70% 55%)"
          />
          <StatCard
            icon={ImageIcon}
            label="图片"
            value={stats.images}
            hint="附件图片"
            delay={0.15}
            accent="hsl(280 60% 60%)"
          />
          <StatCard
            icon={Flame}
            label="连续天数"
            value={streak}
            hint="坚持记录"
            delay={0.2}
            accent="hsl(20 85% 58%)"
          />
        </div>

        {/* Insights */}
        <div className="mt-8">
          <MoodTrend />
        </div>

        {/* Recent */}
        <div className="mt-8">
          <RecentEntries entries={recentEntries} />
        </div>
      </div>
    </div>
  );
}
