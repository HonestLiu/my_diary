import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export interface QueryMessage {
  role: string;
  content: string;
}

export interface TokenUsage {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

/**
 * True when running inside the Tauri desktop shell. The local LLM is only
 * available there; in the browser preview this stays false so the UI can
 * disable the AI features gracefully.
 */
export function isLLMAvailable(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

interface ChunkPayload {
  type?: string;
  id?: number;
  data?: Uint8Array | number[];
  kind?: string;
  timestamp?: number;
}

export interface RunOptions {
  messages: QueryMessage[];
  maxTokens?: number;
  temperature?: number;
  think?: boolean;
  onToken: (text: string) => void;
  onDone?: (usage?: TokenUsage) => void;
  onError?: (msg: string) => void;
  /** Progress / status lines (e.g. "Loading model..."). Not fatal. */
  onStatus?: (msg: string) => void;
}

/**
 * In this plugin the `query-stream-error` event carries a **plain string**
 * payload — both real errors AND streaming status lines (model loading, etc.)
 * are emitted there. We therefore can't rely on a structured `{ msg }`
 * object. Classify the string so genuine failures surface as errors while
 * progress lines stay non-fatal.
 */
const ERROR_WORDS = [
  "error",
  "fail",
  "panic",
  "missing",
  "denied",
  "invalid",
  "could not",
  "cannot",
  "unable",
  "timeout",
  "exception",
  "loadingfile",
  "not found",
];

function isErrorLike(s: string): boolean {
  const l = s.toLowerCase();
  return ERROR_WORDS.some((w) => l.includes(w));
}

function asString(raw: unknown): string {
  if (typeof raw === "string") return raw;
  if (raw && typeof raw === "object") {
    const o = raw as Record<string, unknown>;
    if (typeof o.msg === "string") return o.msg;
    if (typeof o.message === "string") return o.message;
  }
  return String(raw);
}

/**
 * Stream a chat completion from the on-device model via `tauri-plugin-llm`.
 *
 * The plugin ships a JS helper (`tauri-plugin-llm-api`), but we talk to its
 * event protocol directly with the already-installed `@tauri-apps/api` so the
 * project needs no extra npm dependency and the frontend keeps building in
 * environments without the plugin installed.
 *
 *   events:  query-stream-chunk / query-stream-error / query-stream-end
 *   command: plugin:llm|stream
 *
 *   NOTE: `query-stream-error` carries a plain STRING payload (both real
 *   errors and model-loading status lines are emitted there), so we must
 *   parse it as a string — not as a `{ msg }` object.
 */
export async function runLLM(opts: RunOptions): Promise<void> {
  if (!isLLMAvailable()) {
    throw new Error("AI 助手仅在桌面版（已启用本地模型）中可用");
  }

  const un: UnlistenFn[] = [];
  let finished = false;
  const cleanup = () => {
    if (finished) return;
    finished = true;
    un.forEach((u) => u());
  };

  const decode = (data?: Uint8Array | number[]) => {
    if (!data) return "";
    const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
    return new TextDecoder().decode(bytes);
  };

  un.push(
    await listen<ChunkPayload>("query-stream-chunk", (e) => {
      const p = e.payload;
      if (p && p.type === "Chunk") opts.onToken(decode(p.data));
    }),
  );
  un.push(
    await listen<unknown>("query-stream-error", (e) => {
      const msg = asString(e.payload);
      if (!msg) return;
      if (isErrorLike(msg)) {
        opts.onError?.(msg);
        cleanup();
      } else {
        opts.onStatus?.(msg);
      }
    }),
  );
  un.push(
    await listen<{ usage?: TokenUsage }>("query-stream-end", (e) => {
      opts.onDone?.(e.payload?.usage);
      cleanup();
    }),
  );

  try {
    await invoke("plugin:llm|stream", {
      message: {
        type: "Prompt",
        messages: opts.messages,
        tools: [],
        max_tokens: opts.maxTokens ?? 512,
        temperature: opts.temperature ?? 0.7,
        think: opts.think ?? false,
        stream: true,
      },
    });
  } catch (err) {
    opts.onError?.(String(err));
    cleanup();
  }
}

/** List models configured in tauri.conf.json (diagnostics only). */
export async function listLLMModels(): Promise<string[]> {
  if (!isLLMAvailable()) return [];
  return await invoke<string[]>("plugin:llm|list_available_models");
}
