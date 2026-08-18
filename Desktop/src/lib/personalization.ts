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
 * Six curated palettes, aligned with the mobile app's accent seeds
 * (Flutter `accentSeeds` in app_theme.dart). Default is `sky` (天青),
 * matching the mobile default accent so the two apps read as one product.
 */
export const ACCENTS: Record<AccentKey, AccentDef> = {
  amber: {
    key: "amber",
    label: "琥珀",
    swatch: "hsl(26 90% 37%)",
    light: {
      primary: "26 90% 37%",
      primaryForeground: "0 0% 100%",
      accent: "26 70% 95%",
      accentForeground: "26 75% 32%",
      ring: "26 90% 37%",
    },
    dark: {
      primary: "27 92% 55%",
      primaryForeground: "25 30% 10%",
      accent: "26 25% 20%",
      accentForeground: "26 80% 88%",
      ring: "27 92% 55%",
    },
  },
  rose: {
    key: "rose",
    label: "玫瑰",
    swatch: "hsl(345 83% 41%)",
    light: {
      primary: "345 83% 41%",
      primaryForeground: "0 0% 100%",
      accent: "345 60% 96%",
      accentForeground: "345 60% 35%",
      ring: "345 83% 41%",
    },
    dark: {
      primary: "345 84% 62%",
      primaryForeground: "340 40% 12%",
      accent: "340 30% 22%",
      accentForeground: "346 80% 88%",
      ring: "345 84% 62%",
    },
  },
  violet: {
    key: "violet",
    label: "紫罗兰",
    swatch: "hsl(262 61% 58%)",
    light: {
      primary: "262 61% 58%",
      primaryForeground: "0 0% 100%",
      accent: "262 60% 96%",
      accentForeground: "262 55% 38%",
      ring: "262 61% 58%",
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
    label: "翡翠",
    swatch: "hsl(161 94% 30%)",
    light: {
      primary: "161 94% 30%",
      primaryForeground: "0 0% 100%",
      accent: "161 50% 95%",
      accentForeground: "161 55% 28%",
      ring: "161 94% 30%",
    },
    dark: {
      primary: "160 65% 48%",
      primaryForeground: "160 40% 10%",
      accent: "160 28% 20%",
      accentForeground: "160 60% 85%",
      ring: "160 65% 48%",
    },
  },
  sky: {
    key: "sky",
    label: "天青",
    swatch: "hsl(200 98% 39%)",
    light: {
      primary: "200 98% 39%",
      primaryForeground: "0 0% 100%",
      accent: "200 70% 95%",
      accentForeground: "200 60% 32%",
      ring: "200 98% 39%",
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
    label: "岩灰",
    swatch: "hsl(215 19% 35%)",
    light: {
      primary: "215 19% 35%",
      primaryForeground: "0 0% 100%",
      accent: "215 20% 95%",
      accentForeground: "215 25% 25%",
      ring: "215 19% 35%",
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

  const def = ACCENTS[opts.accent] ?? ACCENTS.sky;
  setVars(root, dark ? def.dark : def.light);
  root.style.setProperty(
    "--diary-font",
    opts.font === "serif" ? SERIF_STACK : SANS_STACK,
  );
}
