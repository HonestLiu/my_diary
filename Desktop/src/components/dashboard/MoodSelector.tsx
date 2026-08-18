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
                ? "border-transparent bg-primary text-primary-foreground shadow-soft"
                : "border-border bg-card text-muted-foreground hover:bg-accent hover:text-accent-foreground",
            )}
          >
            <span className="font-mood text-base leading-none">{m.char}</span>
            <span>{m.label}</span>
            {active && (
              <motion.span
                layoutId="mood-dot"
                className="ml-0.5 h-1.5 w-1.5 rounded-full bg-primary-foreground/80"
              />
            )}
          </button>
        );
      })}
    </div>
  );
}
