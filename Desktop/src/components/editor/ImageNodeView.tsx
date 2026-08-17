import { NodeViewWrapper, type NodeViewProps } from "@tiptap/react";
import { useEffect, useRef, useState } from "react";
import { getStorage } from "@/lib/storage";

/** Smallest width (px) a picture can be resized to. */
const MIN_WIDTH = 80;

/**
 * Renders an image whose `src` is a VAULT-RELATIVE path. The relative path is
 * resolved to a renderable URL via the active StorageAdapter (object URL in the
 * browser, data URL on disk in Tauri). This keeps references relative on disk
 * while still displaying correctly in either backend.
 *
 * When selected, a resize handle appears at the bottom-right corner: drag it to
 * freely set the image width (height follows proportionally), or double-click
 * the image to reset back to natural/auto size. The chosen width persists as a
 * Markdown image title (`![alt](src "width=600")`) via the node attribute.
 */
export function ImageNodeView({ node, selected, updateAttributes }: NodeViewProps) {
  const src: string = node.attrs.src ?? "";
  const alt: string = node.attrs.alt ?? "";
  const width: number | null = node.attrs.width ?? null;
  const [url, setUrl] = useState<string>("");
  const imgRef = useRef<HTMLImageElement>(null);

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

  const startResize = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    // If the image is still in auto mode, use its rendered width as the base.
    const startW = width ?? imgRef.current?.clientWidth ?? 320;
    const startX = e.clientX;

    const onMove = (ev: MouseEvent) => {
      const next = Math.max(
        MIN_WIDTH,
        Math.round(startW + (ev.clientX - startX)),
      );
      updateAttributes({ width: next });
    };
    const onUp = () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
    };

    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    document.body.style.cursor = "ew-resize";
    document.body.style.userSelect = "none";
  };

  const resetWidth = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    updateAttributes({ width: null });
  };

  return (
    <NodeViewWrapper className="my-4">
      <div
        className="relative mx-auto w-fit"
        style={width ? { width: `${width}px` } : undefined}
      >
        <img
          ref={imgRef}
          src={url}
          alt={alt}
          draggable={false}
          onDoubleClick={resetWidth}
          title={width ? "双击恢复自适应" : undefined}
          className={`block h-auto max-h-[480px] rounded-2xl shadow-sm transition-shadow ${
            width ? "w-full" : "mx-auto w-auto"
          } ${selected ? "ring-2 ring-primary" : ""}`}
        />
        {selected && (
          <div
            role="slider"
            aria-label="调整图片宽度"
            aria-valuemin={MIN_WIDTH}
            aria-valuemax={2000}
            aria-valuenow={width ?? Math.round(imgRef.current?.clientWidth ?? 0)}
            onMouseDown={startResize}
            title="拖动调整宽度 · 双击图片恢复自适应"
            className="absolute -bottom-2 -right-2 h-4 w-4 cursor-ew-resize rounded-full border-2 border-background bg-primary shadow-md"
          />
        )}
      </div>
    </NodeViewWrapper>
  );
}
