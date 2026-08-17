import { type Extensions, Node, mergeAttributes } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import Underline from "@tiptap/extension-underline";
import Placeholder from "@tiptap/extension-placeholder";
import Image from "@tiptap/extension-image";
import { ReactNodeViewRenderer } from "@tiptap/react";
import { Markdown } from "tiptap-markdown";
import type { Node as PMNode } from "@tiptap/pm/model";
import type { MarkdownSerializerState } from "prosemirror-markdown";
import { ImageNodeView } from "@/components/editor/ImageNodeView";
import { AttachmentNodeView } from "@/components/editor/AttachmentNodeView";
import type { AssetKind } from "@/types/journal";

/**
 * Image node that stores a VAULT-RELATIVE `src` and resolves it for display
 * through the StorageAdapter (see ImageNodeView). Markdown serialization stays
 * the standard `![alt](src)` form, so the file remains portable.
 *
 * A user-chosen width (free resize in the editor) is persisted as the Markdown
 * image title — `![alt](src "width=600")` — which is valid, portable Markdown
 * and stays readable in any other Markdown app. On parse, markdown-it turns the
 * title into the `<img title>` attribute, and the `width` attribute's
 * parseHTML reads it back.
 */
export const ResolvedImage = Image.extend({
  // NOTE: `addAttributes` replaces the parent's, so the original src/alt/title
  // must be re-declared alongside the new `width`.
  addAttributes() {
    return {
      src: { default: null },
      alt: { default: null },
      title: { default: null },
      width: {
        default: null,
        parseHTML: (el) => {
          const raw =
            el.getAttribute("title") ?? el.getAttribute("width") ?? "";
          const m =
            raw.match(/^width=(\d+)$/) ?? raw.match(/^(\d+)$/);
          return m ? Number(m[1]) : null;
        },
        renderHTML: (attrs) =>
          attrs.width ? { title: `width=${attrs.width}` } : {},
      },
    };
  },

  addStorage() {
    return {
      markdown: {
        serialize(state: MarkdownSerializerState, node: PMNode) {
          const src = String(node.attrs.src ?? "")
            .replace(/\(/g, "\\(")
            .replace(/\)/g, "\\)");
          const alt = String(node.attrs.alt ?? "");
          const width = node.attrs.width;
          const realTitle = node.attrs.title
            ? ` "${String(node.attrs.title).replace(/"/g, '\\"')}"`
            : "";
          const title = width ? ` "width=${width}"` : realTitle;
          state.write(`![${alt}](${src}${title})`);
        },
      },
    };
  },

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
      /**
       * Optional user-chosen card width (px). Persisted as `data-width` in the
       * serialized `<attachment>` HTML, so it survives the Markdown round-trip
       * and stays readable/editable by hand.
       */
      width: {
        default: null,
        parseHTML: (el) => {
          const raw = (el as HTMLElement).getAttribute("data-width");
          if (!raw) return null;
          const n = Number(raw);
          return Number.isFinite(n) && n > 0 ? n : null;
        },
        renderHTML: (attrs) =>
          attrs.width ? { "data-width": String(attrs.width) } : {},
      },
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
