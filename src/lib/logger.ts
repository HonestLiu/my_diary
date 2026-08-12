/**
 * Local-only structured logger.
 *
 * Verbosity is controlled by the VITE_LOG_LEVEL env var (debug | info | warn |
 * error). In production builds the default level is "warn" so the console stays
 * quiet; in development it defaults to "debug". Nothing here ever sends data
 * off-device — it only writes to the local console.
 */
type Level = "debug" | "info" | "warn" | "error";

const LEVEL_ORDER: Record<Level, number> = { debug: 0, info: 1, warn: 2, error: 3 };

function currentLevel(): Level {
  const env = import.meta.env as ImportMetaEnv;
  const raw = env.VITE_LOG_LEVEL;
  return raw && (raw as Level) in LEVEL_ORDER ? (raw as Level) : import.meta.env.DEV ? "debug" : "warn";
}

function emit(level: Level, args: unknown[]): void {
  if (LEVEL_ORDER[level] < LEVEL_ORDER[currentLevel()]) return;
  const tag = "[my-diary]";
  const fn =
    level === "error" ? console.error : level === "warn" ? console.warn : console.log;
  fn(tag, level.toUpperCase(), ...args);
}

export const logger = {
  debug: (...args: unknown[]) => emit("debug", args),
  info: (...args: unknown[]) => emit("info", args),
  warn: (...args: unknown[]) => emit("warn", args),
  error: (...args: unknown[]) => emit("error", args),
};
