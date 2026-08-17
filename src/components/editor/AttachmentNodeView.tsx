import { NodeViewWrapper, type NodeViewProps } from "@tiptap/react";
import { useEffect, useState } from "react";
import { FileText, Film, Music, Paperclip } from "lucide-react";
import { getStorage } from "@/lib/storage";
import type { AssetKind } from "@/types/journal";

/**
 * Renders non-image attachments (video / audio / generic file) as a tasteful
 * card. Media get inline players; files get a downloadable card. The `src`
 * attribute is a vault-relative path resolved through the StorageAdapter.
 */
export function AttachmentNodeView({ node, selected }: NodeViewProps) {
  const src: string = node.attrs.src ?? "";
  const name: string = node.attrs.name ?? src.split("/").pop() ?? "file";
  const kind: AssetKind = node.attrs.kind ?? "attachment";
  const size: number = Number(node.attrs.size ?? 0);
  const [url, setUrl] = useState<string>("");

  useEffect(() => {
    let active = true;
    let created: string | null = null;
    getStorage()
      .resolveUrl(src)
      .then((u) => {
        if (!active) return;
        setUrl(u);
        if (u.startsWith("blob:")) created = u;
      })
      .catch(() => undefined);
    return () => {
      active = false;
      if (created) URL.revokeObjectURL(created);
    };
  }, [src]);

  const Icon =
    kind === "video" ? Film : kind === "audio" ? Music : name.match(/\.pdf$/i) ? FileText : Paperclip;

  return (
    <NodeViewWrapper className="my-3">
      <div
        className={`flex items-center gap-3 rounded-2xl border border-border bg-card/70 p-3 shadow-sm backdrop-blur ${
          selected ? "ring-2 ring-primary" : ""
        }`}
      >
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-accent text-primary">
          <Icon className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          {kind === "video" && url && (
            <video src={url} controls className="max-h-64 w-full rounded-lg" />
          )}
          {kind === "audio" && url && (
            <audio src={url} controls className="w-full" />
          )}
          <p className="truncate text-sm font-medium text-foreground">{name}</p>
          <p className="text-xs text-muted-foreground">
            {kind} · {(size / 1024).toFixed(1)} KB
          </p>
        </div>
        {url && kind === "attachment" && (
          <a
            href={url}
            download={name}
            className="shrink-0 rounded-lg px-3 py-1.5 text-sm font-medium text-primary hover:bg-accent"
          >
            下载
          </a>
        )}
      </div>
    </NodeViewWrapper>
  );
}
