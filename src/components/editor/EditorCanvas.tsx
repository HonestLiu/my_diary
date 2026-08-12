import { useEditor, EditorContent, type Editor } from "@tiptap/react";
import { useEffect, useRef } from "react";
import { buildExtensions } from "@/lib/editor/extensions";
import { saveDroppedAssets } from "@/lib/editor/assets";
import { EditorToolbar } from "@/components/editor/EditorToolbar";
import type { AssetRef } from "@/types/journal";

interface Props {
  /** Stable key identifying the loaded entry (e.g. its date). */
  entryKey: string;
  /** Initial Markdown body — only reloaded when `entryKey` changes. */
  initialContent: string;
  /**
   * Bump this to force a content reload even when `entryKey` is unchanged
   * (used after restoring a historical version).
   */
  reloadKey?: number;
  onUpdate: (markdown: string) => void;
  onAssetsAdded: (refs: AssetRef[]) => void;
  onPickImages: (files: File[]) => void;
}

export function EditorCanvas({
  entryKey,
  initialContent,
  reloadKey = 0,
  onUpdate,
  onAssetsAdded,
  onPickImages,
}: Props) {
  const editorRef = useRef<Editor | null>(null);
  const loadedKey = useRef<string>("");
  const loadedReload = useRef<number>(0);

  const insertAssetRefs = (refs: AssetRef[], pos?: number) => {
    const ed = editorRef.current;
    if (!ed || !refs.length) return;
    let chain = ed.chain().focus();
    for (const ref of refs) {
      const node =
        ref.kind === "image"
          ? { type: "image", attrs: { src: ref.path, alt: ref.name ?? "" } }
          : {
              type: "attachment",
              attrs: {
                src: ref.path,
                name: ref.name ?? "",
                kind: ref.kind,
                size: ref.size ?? 0,
              },
            };
      chain =
        pos != null ? chain.insertContentAt(pos, node) : chain.insertContent(node);
    }
    chain.run();
    onAssetsAdded(refs);
  };

  const editor = useEditor({
    extensions: buildExtensions(),
    content: initialContent,
    editorProps: {
      attributes: {
        class:
          "prose-diary focus:outline-none min-h-[60vh] px-1 py-2 text-foreground",
        spellcheck: "false",
      },
      handlePaste: (_view, event) => {
        const dt = event.clipboardData;
        if (!dt || !dt.files.length) return false;
        event.preventDefault();
        void saveDroppedAssets(dt.files).then((refs) =>
          insertAssetRefs(refs),
        );
        return true;
      },
      handleDrop: (view, event) => {
        const dt = event.dataTransfer;
        if (!dt || !dt.files.length) return false;
        event.preventDefault();
        const coords = { left: event.clientX, top: event.clientY };
        const pos = view.posAtCoords(coords)?.pos ?? view.state.selection.from;
        void saveDroppedAssets(dt.files).then((refs) =>
          insertAssetRefs(refs, pos),
        );
        return true;
      },
    },
    onUpdate: ({ editor }) => {
      onUpdate(editor.storage.markdown.getMarkdown() ?? "");
    },
  });

  editorRef.current = editor;

  // Reload content when a different entry is opened OR when a version is
  // restored (reloadKey bump while staying on the same date).
  useEffect(() => {
    const ed = editorRef.current;
    if (!ed) return;
    if (loadedKey.current !== entryKey || loadedReload.current !== reloadKey) {
      loadedKey.current = entryKey;
      loadedReload.current = reloadKey;
      ed.commands.setContent(initialContent, false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entryKey, initialContent, reloadKey]);

  return (
    <div className="flex flex-col">
      <EditorToolbar editor={editor} onPickImages={onPickImages} />
      <EditorContent editor={editor} className="w-full" />
    </div>
  );
}
