import { motion } from "framer-motion";
import { Construction } from "lucide-react";
import type { ReactNode } from "react";

interface PlaceholderProps {
  title: string;
  description: string;
  phase: string;
  icon?: ReactNode;
}

/**
 * Elegant phase placeholder. Replaced by real implementations in later phases.
 */
export default function Placeholder({
  title,
  description,
  phase,
  icon,
}: PlaceholderProps) {
  return (
    <div className="flex h-full items-center justify-center px-8">
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease: "easeOut" }}
        className="flex max-w-md flex-col items-center text-center"
      >
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-accent text-accent-foreground">
          {icon ?? <Construction className="h-7 w-7" />}
        </div>
        <h2 className="mt-5 text-2xl font-semibold tracking-tight">{title}</h2>
        <p className="mt-2 text-muted-foreground">{description}</p>
        <span className="mt-5 rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
          {phase} · 即将在后续阶段实现
        </span>
      </motion.div>
    </div>
  );
}
