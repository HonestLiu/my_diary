import { useMemo, useState, type ChangeEvent } from "react";
import { Cloud, CheckCircle2, AlertTriangle, FolderPlus, Trash2 } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { S3StorageProvider } from "@/lib/sync/s3";
import { SyncEngine, type SyncResult } from "@/lib/sync/engine";
import { uuid } from "@/lib/utils";
import { cn } from "@/lib/utils";
import type { SyncConfig } from "@/types/journal";
import { exportHtml, exportZip } from "@/lib/export";
import { importMarkdownFiles, type ImportConflictPolicy, type ImportResult } from "@/lib/import";
import { isTauri } from "@/lib/storage/types";

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

  const entries = useAppStore((s) => s.entries);

  const vaults = useAppStore((s) => s.vaults);
  const activeVaultId = useAppStore((s) => s.activeVaultId);
  const switchVault = useAppStore((s) => s.switchVault);
  const createVault = useAppStore((s) => s.createVault);
  const renameVault = useAppStore((s) => s.renameVault);
  const removeVault = useAppStore((s) => s.removeVault);

  const [newVaultName, setNewVaultName] = useState("");
  const [newVaultPath, setNewVaultPath] = useState("");
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState("");

  const [importPolicy, setImportPolicy] = useState<ImportConflictPolicy>("skip");
  const [importing, setImporting] = useState(false);
  const [importResult, setImportResult] = useState<ImportResult | null>(null);

  const handleExportZip = async () => {
    const ok = await exportZip(entries);
    if (!ok) {
      window.alert(
        "未安装可选依赖 fflate，已为你导出 HTML 版本。\n如需 .zip，请在项目目录运行：npm i fflate",
      );
      exportHtml(entries);
    }
  };

  const handleCreateVault = async () => {
    await createVault(newVaultName, isTauri() ? newVaultPath : undefined);
    setNewVaultName("");
    setNewVaultPath("");
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
    updateSettings({ sync: form });
    setError(null);
  };

  const applyPreset = (provider: string) => {
    const preset = PRESETS[provider] ?? {};
    setForm((f) => ({ ...f, provider: provider as SyncConfig["provider"], ...preset }));
  };

  const runSync = async () => {
    if (!form.endpoint || !form.bucket || !form.accessKey || !form.secretKey) {
      setError("请先填写完整的存储配置并保存。");
      return;
    }
    setError(null);
    setSyncing(true);
    setResult(null);
    try {
      const remote = new S3StorageProvider({
        endpoint: form.endpoint,
        bucket: form.bucket,
        region: form.region ?? "us-east-1",
        accessKey: form.accessKey,
        secretKey: form.secretKey,
        pathStyle: form.pathStyle ?? false,
      });
      const engine = new SyncEngine(repo.storageAdapter, remote, deviceId);
      const res = await engine.sync();
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
    <div className="h-full overflow-y-auto px-8 py-10">
      <div className="mx-auto max-w-2xl">
        <h1 className="mb-8 text-3xl font-semibold text-foreground">设置</h1>

        {/* Appearance */}
        <Card title="外观">
          <div className="flex gap-2">
            {(["light", "dark", "system"] as const).map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setTheme(t)}
                className={cn(
                  "rounded-xl border px-4 py-2 text-sm transition",
                  settings.theme === t
                    ? "border-amber-400 bg-accent text-amber-700"
                    : "border-border text-muted-foreground hover:bg-muted",
                )}
              >
                {t === "light" ? "浅色" : t === "dark" ? "深色" : "跟随系统"}
              </button>
            ))}
          </div>
        </Card>

        {/* Vaults */}
        <Card title="日记库（多 Vault）">
          <p className="mb-4 text-sm text-muted-foreground">
            可以拥有多个互相独立的日记库（例如「个人」与「工作」），切换即时生效。每个库都是独立的开放 Markdown 文件夹，互不影响。
          </p>

          <div className="space-y-2">
            {vaults.map((v) => {
              const active = v.id === activeVaultId;
              const renaming = renamingId === v.id;
              return (
                <div
                  key={v.id}
                  className={cn(
                    "flex items-center gap-2 rounded-xl border px-3 py-2",
                    active ? "border-amber-400 bg-accent" : "border-border",
                  )}
                >
                  {renaming ? (
                    <input
                      autoFocus
                      value={renameValue}
                      onChange={(e) => setRenameValue(e.target.value)}
                      onBlur={() => {
                        if (renameValue.trim()) renameVault(v.id, renameValue);
                        setRenamingId(null);
                      }}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") {
                          if (renameValue.trim()) renameVault(v.id, renameValue);
                          setRenamingId(null);
                        }
                      }}
                      className="flex-1 rounded-lg border border-border bg-card px-2 py-1 text-sm text-foreground outline-none"
                    />
                  ) : (
                    <button
                      type="button"
                      onClick={() => !active && switchVault(v.id)}
                      className="flex flex-1 items-center gap-2 text-left text-sm"
                    >
                      <span
                        className={cn(
                          "font-medium",
                          active ? "text-amber-700" : "text-foreground",
                        )}
                      >
                        {v.name}
                      </span>
                      {active && (
                        <span className="text-xs text-amber-600">当前</span>
                      )}
                      {!isTauri() && (
                        <span className="truncate text-xs text-muted-foreground">
                          · {v.root}
                        </span>
                      )}
                    </button>
                  )}

                  {!renaming && (
                    <>
                      <button
                        type="button"
                        title="重命名"
                        onClick={() => {
                          setRenamingId(v.id);
                          setRenameValue(v.name);
                        }}
                        className="rounded-md px-2 py-1 text-xs text-muted-foreground hover:bg-muted"
                      >
                        重命名
                      </button>
                      <button
                        type="button"
                        title="删除该日记库"
                        disabled={vaults.length <= 1}
                        onClick={() => {
                          if (
                            window.confirm(
                              `确定删除日记库「${v.name}」？此操作仅从列表中移除，磁盘上的文件需手动删除。`,
                            )
                          ) {
                            void removeVault(v.id);
                          }
                        }}
                        className="rounded-md px-2 py-1 text-xs text-red-500 hover:bg-red-50 disabled:opacity-40"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </>
                  )}
                </div>
              );
            })}
          </div>

          <div className="mt-4 flex flex-wrap items-end gap-2">
            <Labeled label="新日记库名称">
              <input
                value={newVaultName}
                onChange={(e) => setNewVaultName(e.target.value)}
                placeholder="例如：工作笔记"
                className={inputCls}
              />
            </Labeled>
            {isTauri() && (
              <Labeled label="目录（可选，留空用默认位置）">
                <input
                  value={newVaultPath}
                  onChange={(e) => setNewVaultPath(e.target.value)}
                  placeholder="绝对路径，如 D:/Diaries/work"
                  className={inputCls}
                />
              </Labeled>
            )}
            <button
              type="button"
              onClick={handleCreateVault}
              className="flex items-center gap-2 rounded-xl bg-foreground px-4 py-2 text-sm font-medium text-background hover:bg-foreground/90"
            >
              <FolderPlus className="h-4 w-4" />
              新建并切换
            </button>
          </div>
        </Card>

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
              className="flex items-center gap-2 rounded-xl bg-amber-500 px-4 py-2 text-sm font-medium text-white hover:bg-amber-600 disabled:opacity-60"
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
                  key={c.path}
                  className="flex items-center justify-between rounded-xl bg-accent px-3 py-2 text-sm text-amber-700"
                >
                  <span className="truncate">⚠ 冲突：{c.path}</span>
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
              onClick={() => exportHtml(entries)}
              className="rounded-xl bg-foreground px-4 py-2 text-sm font-medium text-background hover:bg-foreground/90"
            >
              导出为单个 HTML
            </button>
            <button
              type="button"
              onClick={handleExportZip}
              className="rounded-xl border border-border px-4 py-2 text-sm font-medium text-foreground hover:bg-muted"
            >
              导出为 Markdown 压缩包 (.zip)
            </button>
          </div>
          <p className="mt-3 text-xs text-muted-foreground">
            .zip 需要可选依赖 fflate：<code>npm i fflate</code>。未安装时此按钮自动降级为 HTML。
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

        <p className="mt-6 text-center text-xs text-muted-foreground">
          数据格式：MyDiary/entries/YYYY/MM/YYYY-MM-DD.md — 停止维护后你仍可直接读取。
        </p>
      </div>
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-6 rounded-2xl border border-border bg-card p-5 shadow-sm">
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
  "rounded-xl border border-border px-3 py-2 text-sm text-foreground outline-none focus:border-amber-300";

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
      <span className={warn ? "font-semibold text-amber-600" : "text-foreground"}>
        {value}
      </span>
    </div>
  );
}
