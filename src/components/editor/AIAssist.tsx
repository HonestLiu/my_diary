import { useRef, useState } from "react";
import { type Editor } from "@tiptap/react";
import { Sparkles, Loader2, X, Copy, Replace, Wand2 } from "lucide-react";
import { runLLM, isLLMAvailable, type QueryMessage } from "@/lib/llm";
import { cn } from "@/lib/utils";

type Mode = "append" | "replace" | "info";

interface Action {
  key: string;
  label: string;
  mode: Mode;
  system: string;
  maxTokens: number;
}

const ACTIONS: Action[] = [
  {
    key: "continue",
    label: "续写",
    mode: "append",
    system:
      "你是写作伙伴。请自然、克制地接着用户日记的脉络续写一段（中文，不超过 120 字），不要重复已有内容，不要加标题或解释。",
    maxTokens: 220,
  },
  {
    key: "polish",
    label: "润色",
    mode: "replace",
    system:
      "请润色下面的日记，使语言更流畅自然、保留原意与语气，仅输出润色后的正文，不要解释或加标题。",
    maxTokens: 400,
  },
  {
    key: "summary",
    label: "总结",
    mode: "info",
    system: "用 2-3 句中文概括这篇日记的核心内容与情绪。",
    maxTokens: 200,
  },
  {
    key: "mood",
    label: "心情",
    mode: "info",
    system:
      "阅读日记，从 [happy, excited, calm, neutral, tired, sad, angry] 中选一个最贴切的心情，并给一句中文理由。只输出：心情=XX；理由=……",
    maxTokens: 120,
  },
];

/**
 * AI 辅助面板：在编辑器内调用本地模型（tauri-plugin-llm）做续写 / 润色 /
 * 总结 / 心情分析。所有推理在用户设备上离线完成，不上传任何服务器。
 */
export function AIAssist({ editor }: { editor: Editor }) {
  const available = isLLMAvailable();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [out, setOut] = useState("");
  const [err, setErr] = useState("");
  const [status, setStatus] = useState("");
  const [cur, setCur] = useState<Action | null>(null);
  const busyRef = useRef(false);
  const wdRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const run = (a: Action) => {
    const text = editor.getText().trim();
    if ((a.mode === "replace" || a.mode === "append") && !text) {
      setErr("先写点内容，再让 AI 帮忙～");
      return;
    }
    setCur(a);
    setBusy(true);
    busyRef.current = true;
    setErr("");
    setOut("");
    setStatus("正在准备模型…");

    // 看门狗：若长时间没有任何事件（模型加载异常 / 推理卡死），给出提示而非无限转圈。
    if (wdRef.current) clearTimeout(wdRef.current);
    wdRef.current = setTimeout(() => {
      if (busyRef.current) {
        setStatus(
          (s) =>
            s ||
            "模型仍在加载或推理中（首次约需数十秒）。若长时间无输出，请查看程序终端日志。",
        );
      }
    }, 45000);

    const finish = () => {
      setBusy(false);
      busyRef.current = false;
      if (wdRef.current) clearTimeout(wdRef.current);
    };

    const messages: QueryMessage[] = [
      { role: "system", content: a.system },
      { role: "user", content: text },
    ];

    runLLM({
      messages,
      maxTokens: a.maxTokens,
      onToken: (t) => {
        if (a.mode === "append") {
          // 流式续写：直接插入到文末，不打断写作。
          editor.chain().focus("end").insertContent(t).run();
        } else {
          setOut((p) => p + t);
        }
      },
      onStatus: (m) => setStatus(m),
      onDone: () => {
        finish();
        if (a.mode === "append") setOut("（已续写到文末）");
        else setStatus("");
      },
      onError: (m) => {
        setErr(m);
        setStatus("");
        finish();
      },
    });
  };

  const copy = () => {
    if (out) navigator.clipboard?.writeText(out);
  };

  const replaceAll = () => {
    if (out && cur?.mode === "replace") {
      editor.chain().focus().setContent(out).run();
      setOut("");
      setCur(null);
      setOpen(false);
    }
  };

  return (
    <div className="relative">
      <button
        type="button"
        title={available ? "AI 辅助（本地模型）" : "AI 助手仅在桌面版可用"}
        aria-label="AI 辅助"
        disabled={!available}
        onMouseDown={(e) => e.preventDefault()}
        onClick={() => setOpen((o) => !o)}
        className={cn(
          "flex h-9 items-center gap-1 rounded-lg px-2 transition",
          open
            ? "bg-accent text-accent-foreground"
            : "text-muted-foreground hover:bg-muted hover:text-foreground",
          !available && "cursor-not-allowed opacity-40",
        )}
      >
        <Sparkles className="h-4 w-4" />
        <span className="text-xs font-medium">AI</span>
      </button>

      {open && (
        <div className="absolute right-0 top-11 z-30 w-80 rounded-2xl border border-border bg-card p-3 shadow-xl">
          <div className="mb-2 flex items-center justify-between">
            <span className="flex items-center gap-1.5 text-sm font-medium">
              <Wand2 className="h-4 w-4 text-primary" /> AI 辅助
            </span>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
              aria-label="关闭"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          <div className="grid grid-cols-2 gap-1.5">
            {ACTIONS.map((a) => (
              <button
                key={a.key}
                type="button"
                disabled={busy}
                onClick={() => run(a)}
                className="flex items-center justify-center gap-1 rounded-lg border border-border px-2 py-2 text-sm transition hover:bg-muted disabled:opacity-50"
              >
                {busy && cur?.key === a.key ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : null}
                {a.label}
              </button>
            ))}
          </div>

          {err && (
            <p className="mt-2 rounded-lg bg-red-500/10 px-2 py-1.5 text-xs text-red-500">
              {err}
            </p>
          )}

          {!err && status && busy && (
            <p className="mt-2 flex items-center gap-1.5 rounded-lg bg-muted/60 px-2 py-1.5 text-xs text-muted-foreground">
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
              <span className="truncate">{status}</span>
            </p>
          )}

          {(out || busy) && cur && cur.mode !== "append" && (
            <div className="mt-2">
              <pre className="max-h-44 overflow-auto whitespace-pre-wrap rounded-lg bg-muted/50 p-2 text-xs leading-relaxed text-foreground">
                {out}
                {busy ? <span className="animate-pulse">▍</span> : null}
              </pre>
              <div className="mt-2 flex gap-2">
                {cur.mode === "replace" && (
                  <button
                    type="button"
                    onClick={replaceAll}
                    disabled={busy || !out}
                    className="flex items-center gap-1 rounded-lg bg-primary px-2.5 py-1.5 text-xs font-medium text-primary-foreground transition hover:opacity-90 disabled:opacity-50"
                  >
                    <Replace className="h-3.5 w-3.5" /> 替换全文
                  </button>
                )}
                <button
                  type="button"
                  onClick={copy}
                  disabled={!out}
                  className="flex items-center gap-1 rounded-lg border border-border px-2.5 py-1.5 text-xs font-medium transition hover:bg-muted disabled:opacity-50"
                >
                  <Copy className="h-3.5 w-3.5" /> 复制
                </button>
              </div>
            </div>
          )}

          {cur && cur.mode === "append" && (out || busy) && (
            <p className="mt-2 text-xs text-muted-foreground">
              {busy ? "正在续写…" : out}
            </p>
          )}

          <p className="mt-2 text-[11px] text-muted-foreground">
            本地 Qwen 模型离线推理，数据不出设备。
          </p>
        </div>
      )}
    </div>
  );
}
