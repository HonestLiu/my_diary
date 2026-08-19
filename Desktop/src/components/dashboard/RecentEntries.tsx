import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { EntryCard } from "@/components/EntryCard";
import { useAppStore } from "@/store/appStore";
import type { JournalEntry } from "@/types/journal";

interface RecentEntriesProps {
  entries: JournalEntry[];
}

export function RecentEntries({ entries }: RecentEntriesProps) {
  const navigate = useNavigate();
  const openEntry = useAppStore((s) => s.openEntry);

  const open = (e: JournalEntry) => {
    openEntry(e.id, e.date);
    navigate("/editor");
  };

  return (
    <section>
      <h3 className="mb-3 px-1 text-base font-semibold">最近日记</h3>
      <div className="flex flex-col gap-3">
        {entries.map((e, i) => (
          <motion.div
            key={e.id}
            initial={{ opacity: 0, x: -8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.3, delay: i * 0.05 }}
          >
            <EntryCard
              title={e.title}
              meta={e.date.slice(5)}
              mood={e.mood}
              weather={e.weather}
              preview={e.body || "（空白日记）"}
              location={e.location}
              tags={e.tags}
              coverPath={e.assets.find((a) => a.kind === "image")?.path}
              onClick={() => open(e)}
            />
          </motion.div>
        ))}
      </div>
    </section>
  );
}
