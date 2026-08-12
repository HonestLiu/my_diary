import { motion } from "framer-motion";
import type { LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

interface StatCardProps {
  icon: LucideIcon;
  label: string;
  value: string | number;
  hint?: string;
  delay?: number;
  accent?: string;
}

export function StatCard({
  icon: Icon,
  label,
  value,
  hint,
  delay = 0,
  accent = "hsl(var(--primary))",
}: StatCardProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, delay, ease: "easeOut" }}
    >
      <Card className="p-5 transition-shadow duration-300 hover:shadow-soft-lg">
        <div className="flex items-center justify-between">
          <span className="text-sm text-muted-foreground">{label}</span>
          <span
            className="flex h-8 w-8 items-center justify-center rounded-lg"
            style={{ backgroundColor: `color-mix(in srgb, ${accent} 14%, transparent)` }}
          >
            <Icon className="h-4 w-4" style={{ color: accent }} />
          </span>
        </div>
        <div className="mt-3 text-3xl font-semibold tracking-tight">{value}</div>
        {hint && (
          <div className={cn("mt-1 text-xs text-muted-foreground")}>{hint}</div>
        )}
      </Card>
    </motion.div>
  );
}
