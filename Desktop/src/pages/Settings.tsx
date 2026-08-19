import { useMemo, useRef, useState, type ChangeEvent } from "react";
import { Cloud, CheckCircle2, AlertTriangle, Download, Upload, X } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { invoke } from "@tauri-apps/api/core";
import { isTauri } from "@/lib/storage/types";
import type { SyncResult } from "@/types/journal";
import { uuid } from "@/lib/utils";
import { cn } from "@/lib/utils";
import type { SyncConfig } from "@/types/journal";
import { importMarkdownFiles, type ImportConflictPolicy, type ImportResult } from "@/lib/import";
import { Avatar } from "@/components/Avatar";
import { profileAvatarPath } from "@/lib/vault";
import { ACCENT_LIST } from "@/lib/personalization";

const DEVICE_KEY = "my-diary-device-id";

function getDeviceId(): string {
  if (typeof localStorage === "undefined") return "device-local";
  let id = localStorage.getItem(DEVICE_KEY);
  if (!id) {
    id = uuid();
    localStorage.setItem(DEVICE_KEY, id);
  }
  return id;
}

const PRESETS: Record<string, Partial<SyncConfig>> = {
  s3: {
    endpoint: "https://s3.us-east-1.amazonaws.com",
    region: "us-east-1",
    pathStyle: false,
  },
  r2: {
    endpoint: "https://<accountid>.r2.cloudflarestorage.com",
    region: "auto",
    pathStyle: true,
  },
  minio: {
    endpoint: "http://localhost:9000",
    region: "us-east-1",
    pathStyle: true,
  },
  oss: {
    endpoint: "https://oss-cn-hangzhou.aliyuncs.com",
    region: "oss-cn-hangzhou",
    pathStyle: true,
  },
};

/** Settings — appearance + object-storage sync (S3 / R2 / MinIO / OSS). */
export default function Settings() {
  const repo = useAppStore((s) => s.repo);
  const settings = useAppStore((s) => s.settings);
  const setTheme = useAppStore((s) => s.setTheme);
  const updateSettings = useAppStore((s) => s.updateSettings);

  const sync = settings.sync ?? {
    enabled: false,
    provider: "none",
  };
  const [form, setForm] = useState<SyncConfig>(sync);
  const [syncing, setSyncing] = useState(false);
  const [result, setResult] = useState<SyncResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [importPolicy, setImportPolicy] = useState<ImportConflictPolicy>("skip");
  const [importing, setImporting] = useState(false);
  const [importResult, setImportResult] = useState<ImportResult | null>(null);

  const setExportOpen = useAppStore((s) => s.setExportOpen);
  const avatarInputRef = useRef<HTMLInputElement | null>(null);
  const [avatarBusy, setAvatarBusy] = useState(false);

  /** 选择图片写入 vault profile/，更新 settings.avatar。 */
  const handleAvatarFile = async (file: File | undefined) => {
    if (!file) return;
    setAvatarBusy(true);
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      const ext = safeImageExt(file.name) || ".png";
      const rel = profileAvatarPath(`avatar${ext}`);
      await repo.storageAdapter.writeBytes(rel, bytes);
      updateSettings({ avatar: rel });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setAvatarBusy(false);
      if (avatarInputRef.current) avatarInputRef.current.value = "";
    }
  };

  /** 移除头像：删除 vault 文件并清空 settings.avatar。 */
  const handleClearAvatar = async () => {
    const cur = settings.avatar;
    updateSettings({ avatar: "" });
    if (cur.trim()) {
      await repo.storageAdapter.delete(cur).catch(() => undefined);
    }
  };

  const handleImport = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    setImporting(true);
    setImportResult(null);
    try {
      const res = await importMarkdownFiles(
        useAppStore.getState().repo,
        Array.from(files),
        importPolicy,
      );
      setImportResult(res);
      await useAppStore.getState().refresh();
    } finally {
      setImporting(false);
    }
  };

  const deviceId = useMemo(() => getDeviceId(), []);

  const save = () => {
    // 桌面端 UI 没有「启用同步」开关：provider 选定即视为启用，
    // 归一化 enabled 使落盘配置语义一致（移动端 / 后续逻辑可依赖）。
    updateSettings({ sync: { ...form, enabled: form.provider !== "none" } });
    setError(null);
  };

  const applyPreset = (provider: string) => {
    const preset = PRESETS[provider] ?? {};
    setForm((f) => ({ ...f, provider: provider as SyncConfig["provider"], ...preset }));
  };

  const runSync = async () => {
    if (!isTauri()) {
      setError("云同步仅在桌面端（Tauri）可用。");
      return;
    }
    if (!form.endpoint || !form.bucket || !form.accessKey || !form.secretKey) {
      setError("请先填写完整的存储配置并保存。");
      return;
    }
    const vaultRoot = useAppStore.getState().repo.vaultRoot;
    if (!vaultRoot) {
      setError("未找到 vault 根目录。");
      return;
    }
    setError(null);
    setSyncing(true);
    setResult(null);
    try {
      // 同步逻辑完全在 Rust 侧（src-tauri/src/sync.rs），前端只调用命令。
      const res = await invoke<SyncResult>("sync_vault", {
        vaultRoot,
        config: form,
      });
      setResult(res);
      await useAppStore.getState().refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSyncing(false);
    }
  };

  const field = (key: keyof SyncConfig) => ({
    value: typeof form[key] === "string" ? (form[key] as string) : "",
    onChange: (e: ChangeEvent<HTMLInputElement>) =>
      setForm((f) => ({ ...f, [key]: e.target.value })),
  });

  return (
    <div className="h-full overflow-y-auto px-6 py-6">
      <div className="mx-auto max-w-5xl">
        <h1 className="mb-6 text-2xl font-semibold tracking-tight text-foreground">
          设置
        </h1>

        <div className="grid gap-6 lg:grid-cols-2">
          <div className="space-y-6">
            {/* Appearance */}
        <Card title="外观">
          <div className="space-y-5">
            {/* Theme mode */}
            <div>
              <div className="mb-2 text-xs font-medium text-muted-foreground">主题</div>
              <div className="flex gap-2">
                {(
                  [
                    { k: "light", label: "浅色" },
                    { k: "dark", label: "深色" },
                    { k: "system", label: "跟随系统" },
                  ] as const
                ).map((t) => (
                  <button
                    key={t.k}
                    type="button"
                    onClick={() => setTheme(t.k)}
                    className={cn(
                      "rounded-xl border px-4 py-2 text-sm transition",
                      settings.theme === t.k
                        ? "border-primary bg-accent text-primary"
                        : "border-border text-muted-foreground hover:bg-muted",
                    )}
                  >
                    {t.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Accent color */}
            <div>
              <div className="mb-2 text-xs font-medium text-muted-foreground">
                主题色
              </div>
              <div className="flex flex-wrap gap-2">
                {ACCENT_LIST.map((a) => (
                  <button
                    key={a.key}
                    type="button"
                    title={a.label}
                    aria-label={a.label}
                    onClick={() => updateSettings({ accent: a.key })}
                    className={cn(
                      "flex items-center gap-2 rounded-xl border px-3 py-2 text-sm transition",
                      settings.accent === a.key
                        ? "border-primary bg-accent text-primary"
                        : "border-border text-muted-foreground hover:bg-muted",
                    )}
                  >
                    <span
                      className="h-4 w-4 rounded-full ring-1 ring-inset ring-black/10"
                      style={{ background: a.swatch }}
                    />
                    {a.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Diary font */}
            <div>
              <div className="mb-2 text-xs font-medium text-muted-foreground">
                正文字体
              </div>
              <div className="flex gap-2">
                {(
                  [
                    { k: "sans", label: "无衬线" },
                    { k: "serif", label: "衬线" },
                  ] as const
                ).map((f) => (
                  <button
                    key={f.k}
                    type="button"
                    onClick={() => updateSettings({ font: f.k })}
                    className={cn(
                      "rounded-xl border px-4 py-2 text-sm transition",
                      settings.font === f.k
                        ? "border-primary bg-accent text-primary"
                        : "border-border text-muted-foreground hover:bg-muted",
                    )}
                  >
                    {f.label}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </Card>

        {/* Profile / personalization */}
        <Card title="个人资料">
          <p className="mb-4 text-sm text-muted-foreground">
            设置你的名字，会显示在应用角落与导出的日记中，让记录更有「你」的气息。
          </p>
          <Labeled label="头像">
            <div className="flex items-center gap-3">
              <Avatar
                avatar={settings.avatar}
                name={settings.displayName}
                size={56}
              />
              <div className="flex flex-col gap-1.5">
                <input
                  ref={avatarInputRef}
                  type="file"
                  accept="image/png,image/jpeg,image/webp,image/gif"
                  className="hidden"
                  onChange={(e) => void handleAvatarFile(e.target.files?.[0])}
                />
                <button
                  type="button"
                  onClick={() => avatarInputRef.current?.click()}
                  disabled={avatarBusy}
                  className="flex items-center gap-1.5 rounded-lg border border-border px-3 py-1.5 text-sm text-foreground transition hover:bg-muted disabled:opacity-60"
                >
                  <Upload className="h-3.5 w-3.5" />
                  {avatarBusy ? "上传中…" : "选择图片"}
                </button>
                {settings.avatar && (
                  <button
                    type="button"
                    onClick={() => void handleClearAvatar()}
                    className="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm text-red-500 transition hover:bg-red-50"
                  >
                    <X className="h-3.5 w-3.5" />
                    移除头像
                  </button>
                )}
              </div>
            </div>
          </Labeled>
          <div className="mt-4">
            <Labeled label="座右铭">
              <input
                value={settings.motto}
                onChange={(e) => updateSettings({ motto: e.target.value })}
                placeholder="写一句鼓舞自己的话…"
                maxLength={60}
                className={inputCls}
              />
            </Labeled>
            <p className="mt-1 text-xs text-muted-foreground">
              会显示在侧边栏个人资料下方，让应用更有「你」的气息。
            </p>
          </div>
          <div className="mt-4">
            <Labeled label="昵称 / 署名">
              <input
                value={settings.displayName}
                onChange={(e) => updateSettings({ displayName: e.target.value })}
                placeholder="例如：小林"
                className={inputCls}
              />
            </Labeled>
          </div>
          <div className="mt-4">
            <div className="mb-2 text-xs font-medium text-muted-foreground">
              日历每周从
            </div>
            <div className="flex gap-2">
              {([{ k: 1 as const, label: "周一" }, { k: 0 as const, label: "周日" }]).map(
                (w) => (
                  <button
                    key={w.k}
                    type="button"
                    onClick={() => updateSettings({ weekStartsOn: w.k })}
                    className={cn(
                      "rounded-xl border px-4 py-2 text-sm transition",
                      settings.weekStartsOn === w.k
                        ? "border-primary bg-accent text-primary"
                        : "border-border text-muted-foreground hover:bg-muted",
                    )}
                  >
                    {w.label}
                  </button>
                ),
              )}
            </div>
          </div>
        </Card>

        {/* 媒体压缩 */}
        <Card title="媒体">
          <div className="mb-4">
            <div className="mb-1 text-sm font-medium text-foreground">
              图片上传压缩
            </div>
            <p className="mb-2 text-xs text-muted-foreground">
              导入图片时按此质量重压缩（上限 2000px 长边）并生成列表缩略图。
            </p>
            <QualitySlider
              value={settings.imageCompressQuality}
              onChange={(v) => updateSettings({ imageCompressQuality: v })}
            />
          </div>
          <div>
            <div className="mb-1 text-sm font-medium text-foreground">
              视频上传压缩
            </div>
            <p className="mb-2 text-xs text-muted-foreground">
              导入视频时按此质量压缩（100 为不压缩）并抽取封面帧。
            </p>
            <QualitySlider
              value={settings.videoCompressQuality}
              onChange={(v) => updateSettings({ videoCompressQuality: v })}
            />
          </div>
          <p className="mt-4 text-xs text-muted-foreground">
            两项均只影响之后导入的素材，已存在的图片/视频不会被重新处理。
          </p>
        </Card>

          </div>
          {/* Right column */}
          <div className="space-y-6">
            {/* Sync */}
            <Card title="云同步（对象存储）">
          <p className="mb-4 text-sm text-muted-foreground">
            兼容 AWS S3 / Cloudflare R2 / MinIO / 阿里云 OSS。你的日记正文始终以开放
            Markdown 存于本地，云端仅为备份镜像。
          </p>

          <div className="mb-4 flex flex-wrap gap-2">
            {Object.keys(PRESETS).map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => applyPreset(p)}
                className="rounded-lg border border-border px-3 py-1.5 text-sm text-muted-foreground hover:bg-muted"
              >
                {p.toUpperCase()}
              </button>
            ))}
          </div>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Labeled label="Endpoint">
              <input className={inputCls} {...field("endpoint")} placeholder="https://..." />
            </Labeled>
            <Labeled label="Bucket">
              <input className={inputCls} {...field("bucket")} placeholder="my-diary" />
            </Labeled>
            <Labeled label="Region">
              <input className={inputCls} {...field("region")} placeholder="us-east-1" />
            </Labeled>
            <Labeled label="Access Key">
              <input className={inputCls} {...field("accessKey")} />
            </Labeled>
            <Labeled label="Secret Key" full>
              <input className={inputCls} type="password" {...field("secretKey")} />
            </Labeled>
            <Labeled label="Path Style" full>
              <label className="flex items-center gap-2 text-sm text-muted-foreground">
                <input
                  type="checkbox"
                  checked={!!form.pathStyle}
                  onChange={(e) => setForm((f) => ({ ...f, pathStyle: e.target.checked }))}
                />
                MinIO / R2 / OSS 通常开启
              </label>
            </Labeled>
          </div>

          <div className="mt-4 flex items-center gap-3">
            <button
              type="button"
              onClick={save}
              className="rounded-xl bg-foreground px-4 py-2 text-sm font-medium text-background hover:bg-foreground/90"
            >
              保存配置
            </button>
            <button
              type="button"
              onClick={runSync}
              disabled={syncing}
              className="flex items-center gap-2 rounded-xl bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-60"
            >
              <Cloud className="h-4 w-4" />
              {syncing ? "同步中…" : "立即同步"}
            </button>
            <span className="text-xs text-muted-foreground">设备 ID: {deviceId.slice(0, 8)}</span>
          </div>

          {error && (
            <div className="mt-4 flex items-center gap-2 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-600">
              <AlertTriangle className="h-4 w-4" />
              {error}
            </div>
          )}

          {result && (
            <div className="mt-4 space-y-2">
              <SyncStat label="已上传" value={result.uploaded.length} />
              <SyncStat label="已下载" value={result.downloaded.length} />
              <SyncStat
                label="冲突"
                value={result.conflicts.length}
                warn={result.conflicts.length > 0}
              />
              {result.conflicts.map((c) => (
                <div
                  key={c}
                  className="flex items-center justify-between rounded-xl bg-accent px-3 py-2 text-sm text-primary"
                >
                  <span className="truncate">⚠ 冲突：{c}</span>
                </div>
              ))}
              {result.errors.length > 0 && (
                <div className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-600">
                  {result.errors.map((e, i) => (
                    <div key={i}>{e}</div>
                  ))}
                </div>
              )}
              {result.conflicts.length === 0 && result.errors.length === 0 && (
                <div className="flex items-center gap-2 text-sm text-green-600">
                  <CheckCircle2 className="h-4 w-4" />
                  同步完成
                </div>
              )}
            </div>
          )}
        </Card>

        {/* Export */}
        <Card title="数据导出（带走你的日记）">
          <p className="mb-4 text-sm text-muted-foreground">
            日记正文以开放 Markdown 保存。导出后可用任何文本编辑器或笔记软件打开，软件停止维护也不丢失数据。
          </p>
          <div className="flex flex-wrap gap-3">
            <button
              type="button"
              onClick={() => setExportOpen(true)}
              className="flex items-center gap-2 rounded-xl bg-foreground px-4 py-2 text-sm font-medium text-background hover:bg-foreground/90"
            >
              <Download className="h-4 w-4" />
              导出日记数据
            </button>
          </div>
          <p className="mt-3 text-xs text-muted-foreground">
            可导出为单个 HTML，或包含全部 Markdown 与图片 / 音频 / 附件的 .zip 压缩包，解压后即可离线阅读。
          </p>
        </Card>

        {/* Import */}
        <Card title="数据导入（把日记带进来）">
          <p className="mb-4 text-sm text-muted-foreground">
            从任意 Markdown 文件批量导入（支持 MyDiary 导出的格式，或任何带 YAML 头 / 文件名为日期的笔记）。导入后立刻出现在时间轴与搜索中。
          </p>

          <div className="mb-4 flex flex-wrap gap-3">
            <label className="cursor-pointer rounded-xl bg-foreground px-4 py-2 text-sm font-medium text-background hover:bg-foreground/90">
              选择 Markdown 文件
              <input
                type="file"
                accept=".md,.markdown,.txt"
                multiple
                className="hidden"
                onChange={(e) => handleImport(e.target.files)}
              />
            </label>
            <label className="cursor-pointer rounded-xl border border-border px-4 py-2 text-sm font-medium text-foreground hover:bg-muted">
              导入整个文件夹
              <input
                type="file"
                /* @ts-expect-error webkitdirectory is non-standard but supported */
                webkitdirectory=""
                directory=""
                multiple
                className="hidden"
                onChange={(e) => handleImport(e.target.files)}
              />
            </label>
          </div>

          <div className="mb-4 flex items-center gap-4 text-sm text-muted-foreground">
            <span>遇到同日期日记：</span>
            <label className="flex items-center gap-1.5">
              <input
                type="radio"
                checked={importPolicy === "skip"}
                onChange={() => setImportPolicy("skip")}
              />
              跳过已有
            </label>
            <label className="flex items-center gap-1.5">
              <input
                type="radio"
                checked={importPolicy === "overwrite"}
                onChange={() => setImportPolicy("overwrite")}
              />
              覆盖
            </label>
          </div>

          {importing && (
            <div className="text-sm text-muted-foreground">导入中…</div>
          )}
          {importResult && (
            <div className="space-y-1 text-sm">
              <div className="flex items-center gap-2 text-green-600">
                <CheckCircle2 className="h-4 w-4" />
                已导入 {importResult.imported} 篇
              </div>
              {importResult.skipped > 0 && (
                <div className="text-muted-foreground">
                  跳过重复 {importResult.skipped} 篇
                </div>
              )}
              {importResult.errors > 0 && (
                <div className="flex items-center gap-2 text-red-500">
                  <AlertTriangle className="h-4 w-4" />
                  {importResult.errors} 篇读取失败
                </div>
              )}
            </div>
          )}
        </Card>

          </div>
        </div>

        <p className="mt-6 text-center text-xs text-muted-foreground">
          数据格式：MyDiary/entries/YYYY/MM/YYYY-MM-DD.md — 停止维护后你仍可直接读取。
        </p>
      </div>
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-border bg-card p-5 shadow-sm">
      <h2 className="mb-3 text-lg font-semibold text-foreground">{title}</h2>
      {children}
    </div>
  );
}

function Labeled({
  label,
  children,
  full,
}: {
  label: string;
  children: React.ReactNode;
  full?: boolean;
}) {
  return (
    <label className={cn("flex flex-col gap-1", full && "sm:col-span-2")}>
      <span className="text-xs text-muted-foreground">{label}</span>
      {children}
    </label>
  );
}

const inputCls =
  "rounded-xl border border-border px-3 py-2 text-sm text-foreground outline-none focus:border-primary";

function SyncStat({
  label,
  value,
  warn,
}: {
  label: string;
  value: number;
  warn?: boolean;
}) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className={warn ? "font-semibold text-primary" : "text-foreground"}>
        {value}
      </span>
    </div>
  );
}

/** 从文件名取安全的图片扩展名（含点）；未知时返回空串。 */
function safeImageExt(fileName: string): string {
  const ext = fileName.split(".").pop()?.toLowerCase() ?? "";
  return /^(png|jpe?g|webp|gif)$/.test(ext) ? `.${ext === "jpeg" ? "jpg" : ext}` : "";
}

/** 1–100 压缩质量滑块 + 数值标签。 */
function QualitySlider({
  value,
  onChange,
}: {
  value: number;
  onChange: (v: number) => void;
}) {
  return (
    <div className="flex items-center gap-3">
      <input
        type="range"
        min={1}
        max={100}
        step={1}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="h-1.5 flex-1 cursor-pointer appearance-none rounded-full bg-muted accent-primary"
      />
      <span className="w-8 shrink-0 text-right text-sm font-semibold text-foreground">
        {value}
      </span>
    </div>
  );
}
