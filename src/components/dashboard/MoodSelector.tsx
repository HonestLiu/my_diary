import { motion } from "framer-motion";
import { MOODS } from "@/lib/constants";
import { cn } from "@/lib/utils";
import type { Mood } from "@/types/journal";

interface MoodSelectorProps {
  value?: Mood;
  onSelect?: (mood: Mood) => void;
}

export function MoodSelector({ value, onSelect }: MoodSelectorProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {MOODS.map((m) => {
        const active = value === m.key;
        return (
          <button
            key={m.key}
            type="button"
            onClick={() => onSelect?.(m.key)}
            className={cn(
              "flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition-all duration-200",
              active
                ? "border-transparent text-white shadow-soft"
                : "border-border bg-card text-muted-foreground hover:bg-accent hover:text-accent-foreground",
            )}
            style={active ? { backgroundColor: m.color } : undefined}
          >
            <span className="text-base leading-none">{m.emoji}</span>
            <span>{m.label}</span>
            {active && (
              <motion.span
                layoutId="mood-dot"
                className="ml-0.5 h-1.5 w-1.5 rounded-full bg-white/80"
              />
            )}
          </button>
        );
      })}
    </div>
  );
}
