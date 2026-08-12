import { NodeViewWrapper, type NodeViewProps } from "@tiptap/react";
import { useEffect, useState } from "react";
import { getStorage } from "@/lib/storage";

/**
 * Renders an image whose `src` is a VAULT-RELATIVE path. The relative path is
 * resolved to a renderable URL via the active StorageAdapter (object URL in the
 * browser, data URL on disk in Tauri). This keeps references relative on disk
 * while still displaying correctly in either backend.
 */
export function ImageNodeView({ node, selected }: NodeViewProps) {
  const src: string = node.attrs.src ?? "";
  const alt: string = node.attrs.alt ?? "";
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

  return (
    <NodeViewWrapper className="my-4">
      <img
        src={url}
        alt={alt}
        draggable={false}
        className={`mx-auto max-h-[480px] w-auto rounded-2xl shadow-sm transition ${
          selected ? "ring-2 ring-amber-400" : ""
        }`}
      />
    </NodeViewWrapper>
  );
}
