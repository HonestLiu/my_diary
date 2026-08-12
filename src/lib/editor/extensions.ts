import { type Extensions, Node, mergeAttributes } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import Underline from "@tiptap/extension-underline";
import Placeholder from "@tiptap/extension-placeholder";
import Image from "@tiptap/extension-image";
import { ReactNodeViewRenderer } from "@tiptap/react";
import { Markdown } from "tiptap-markdown";
import { ImageNodeView } from "@/components/editor/ImageNodeView";
import { AttachmentNodeView } from "@/components/editor/AttachmentNodeView";
import type { AssetKind } from "@/types/journal";

/**
 * Image node that stores a VAULT-RELATIVE `src` and resolves it for display
 * through the StorageAdapter (see ImageNodeView). Markdown serialization stays
 * the standard `![alt](src)` form, so the file remains portable.
 */
export const ResolvedImage = Image.extend({
  addNodeView() {
    return ReactNodeViewRenderer(ImageNodeView);
  },
});

/**
 * Block-level attachment card for video / audio / generic files. Serialized as
 * inline HTML (`<attachment …>`) which survives the Markdown round-trip when
 * the `Markdown` extension runs with `html: true`. The actual bytes always live
 * on disk under `assets/<kind>/`, referenced relatively.
 */
export const Attachment = Node.create({
  name: "attachment",
  group: "block",
  atom: true,
  selectable: true,
  draggable: true,

  addAttributes() {
    return {
      src: { default: "" },
      name: { default: "" },
      kind: { default: "attachment" as AssetKind },
      size: { default: 0 },
    };
  },

  parseHTML() {
    return [
      {
        tag: "attachment",
        getAttrs: (el) => ({
          src: (el as HTMLElement).getAttribute("data-src") ?? "",
          name: (el as HTMLElement).getAttribute("data-name") ?? "",
          kind: (el as HTMLElement).getAttribute("data-kind") ?? "attachment",
          size: Number((el as HTMLElement).getAttribute("data-size") ?? 0),
        }),
      },
    ];
  },

  renderHTML({ HTMLAttributes }) {
    return [
      "attachment",
      mergeAttributes(HTMLAttributes, {
        "data-src": HTMLAttributes.src,
        "data-name": HTMLAttributes.name,
        "data-kind": HTMLAttributes.kind,
        "data-size": HTMLAttributes.size,
      }),
    ];
  },

  addNodeView() {
    return ReactNodeViewRenderer(AttachmentNodeView);
  },
});

/** The canonical extension set for the journal editor. */
export function buildExtensions(): Extensions {
  return [
    StarterKit.configure({
      heading: { levels: [1, 2, 3] },
    }),
    Underline,
    Placeholder.configure({
      placeholder: "今天发生了什么？开始记录吧…",
    }),
    Markdown.configure({
      html: true,
      tightLists: true,
      linkify: true,
      breaks: false,
    }),
    ResolvedImage.configure({ inline: false, allowBase64: false }),
    Attachment,
  ];
}
