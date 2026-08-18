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
  const startNewEntry = useAppStore((s) => s.startNewEntry);

  // Always a brand-new entry, even if today already has some.
  const startRecording = () => {
    startNewEntry(formatDateKey(today));
    navigate("/editor");
  };

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

        {/* Stats row */}
        <div className="mt-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
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
          />
          <StatCard
            icon={ImageIcon}
            label="图片"
            value={stats.images}
            hint="附件图片"
            delay={0.15}
          />
          <StatCard
            icon={Flame}
            label="连续天数"
            value={streak}
            hint="坚持记录"
            delay={0.2}
          />
        </div>

        {/* Body: recent entries (wide) + mood trend (narrow) */}
        <div className="mt-6 grid grid-cols-1 gap-6 xl:grid-cols-3">
          <div className="xl:col-span-2">
            <RecentEntries entries={recentEntries} />
          </div>
          <div className="xl:col-span-1">
            <MoodTrend />
          </div>
        </div>
      </div>
    </div>
  );
}
