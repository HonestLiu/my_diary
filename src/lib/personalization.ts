/**
 * Personalization engine.
 *
 * The app's whole color scheme is driven by semantic CSS variables
 * (`--primary`, `--accent`, `--ring`, …) that Tailwind maps to utility classes
 * (`bg-primary`, `text-accent-foreground`, `ring-ring`, …). By overwriting
 * those variables on the document root we can recolor the entire UI from a
 * single chosen accent — without rebuilding Tailwind or touching component
 * markup beyond swapping a few hardcoded colors for their tokens.
 *
 * `applyAppearance` is the single entry point: call it whenever the user's
 * theme / accent / font preference changes, and it keeps <html> in sync.
 */
import type { AccentKey, FontKey, Theme } from "@/types/journal";

/** The HSL-triplet values that back the semantic Tailwind colors. */
export interface AccentVars {
  primary: string;
  primaryForeground: string;
  accent: string;
  accentForeground: string;
  ring: string;
}

export interface AccentDef {
  key: AccentKey;
  label: string;
  /** A representative color for the picker swatch (CSS color). */
  swatch: string;
  light: AccentVars;
  dark: AccentVars;
}

/**
 * Six curated palettes. The default `amber` intentionally reproduces the
 * original warm "paper" theme so existing installs see no visual change until
 * they pick a different accent.
 */
export const ACCENTS: Record<AccentKey, AccentDef> = {
  amber: {
    key: "amber",
    label: "暖琥珀",
    swatch: "hsl(24 70% 54%)",
    light: {
      primary: "24 70% 54%",
      primaryForeground: "30 40% 99%",
      accent: "22 60% 95%",
      accentForeground: "24 60% 38%",
      ring: "24 70% 54%",
    },
    dark: {
      primary: "24 72% 58%",
      primaryForeground: "25 14% 10%",
      accent: "25 14% 20%",
      accentForeground: "38 24% 88%",
      ring: "24 72% 58%",
    },
  },
  rose: {
    key: "rose",
    label: "蔷薇粉",
    swatch: "hsl(346 77% 50%)",
    light: {
      primary: "346 77% 50%",
      primaryForeground: "0 0% 100%",
      accent: "346 60% 96%",
      accentForeground: "346 60% 35%",
      ring: "346 77% 50%",
    },
    dark: {
      primary: "346 84% 62%",
      primaryForeground: "340 40% 12%",
      accent: "340 30% 22%",
      accentForeground: "346 80% 88%",
      ring: "346 84% 62%",
    },
  },
  violet: {
    key: "violet",
    label: "紫罗兰",
    swatch: "hsl(262 70% 56%)",
    light: {
      primary: "262 70% 56%",
      primaryForeground: "0 0% 100%",
      accent: "262 60% 96%",
      accentForeground: "262 55% 38%",
      ring: "262 70% 56%",
    },
    dark: {
      primary: "263 80% 68%",
      primaryForeground: "263 40% 12%",
      accent: "263 30% 22%",
      accentForeground: "263 80% 90%",
      ring: "263 80% 68%",
    },
  },
  emerald: {
    key: "emerald",
    label: "松石绿",
    swatch: "hsl(152 60% 40%)",
    light: {
      primary: "152 60% 40%",
      primaryForeground: "0 0% 100%",
      accent: "152 50% 95%",
      accentForeground: "152 55% 28%",
      ring: "152 60% 40%",
    },
    dark: {
      primary: "152 65% 50%",
      primaryForeground: "152 40% 10%",
      accent: "152 28% 20%",
      accentForeground: "152 60% 85%",
      ring: "152 65% 50%",
    },
  },
  sky: {
    key: "sky",
    label: "晴空蓝",
    swatch: "hsl(205 85% 48%)",
    light: {
      primary: "205 85% 48%",
      primaryForeground: "0 0% 100%",
      accent: "205 70% 95%",
      accentForeground: "205 60% 32%",
      ring: "205 85% 48%",
    },
    dark: {
      primary: "199 90% 60%",
      primaryForeground: "200 40% 12%",
      accent: "200 30% 22%",
      accentForeground: "199 85% 90%",
      ring: "199 90% 60%",
    },
  },
  slate: {
    key: "slate",
    label: "石墨灰",
    swatch: "hsl(215 20% 35%)",
    light: {
      primary: "215 20% 35%",
      primaryForeground: "0 0% 100%",
      accent: "215 20% 95%",
      accentForeground: "215 25% 25%",
      ring: "215 20% 35%",
    },
    dark: {
      primary: "215 20% 70%",
      primaryForeground: "215 25% 12%",
      accent: "215 18% 22%",
      accentForeground: "215 20% 88%",
      ring: "215 20% 70%",
    },
  },
};

export const ACCENT_LIST: AccentDef[] = Object.values(ACCENTS);

const SANS_STACK =
  '-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Helvetica Neue", Arial, sans-serif';
const SERIF_STACK = 'Georgia, "Songti SC", "Noto Serif SC", "SimSun", serif';

/** True when the OS prefers a dark color scheme. */
export function systemPrefersDark(): boolean {
  return (
    typeof window !== "undefined" &&
    !!window.matchMedia?.("(prefers-color-scheme: dark)").matches
  );
}

/** Resolve the effective light/dark mode from a user's theme choice. */
export function resolveDark(theme: Theme): boolean {
  if (theme === "dark") return true;
  if (theme === "system") return systemPrefersDark();
  return false;
}

function setVars(root: HTMLElement, v: AccentVars) {
  root.style.setProperty("--primary", v.primary);
  root.style.setProperty("--primary-foreground", v.primaryForeground);
  root.style.setProperty("--accent", v.accent);
  root.style.setProperty("--accent-foreground", v.accentForeground);
  root.style.setProperty("--ring", v.ring);
}

/**
 * Push the user's appearance preferences onto the document root. Idempotent —
 * safe to call on every preference change and on every system-theme change.
 */
export function applyAppearance(opts: {
  theme: Theme;
  accent: AccentKey;
  font: FontKey;
}): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  const dark = resolveDark(opts.theme);

  root.classList.toggle("dark", dark);
  root.style.colorScheme = dark ? "dark" : "light";

  const def = ACCENTS[opts.accent] ?? ACCENTS.amber;
  setVars(root, dark ? def.dark : def.light);
  root.style.setProperty(
    "--diary-font",
    opts.font === "serif" ? SERIF_STACK : SANS_STACK,
  );
}
