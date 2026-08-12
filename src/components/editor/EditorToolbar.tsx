import { type Editor } from "@tiptap/react";
import { useRef } from "react";
import {
  Bold,
  Italic,
  Underline as UnderlineIcon,
  Strikethrough,
  Heading1,
  Heading2,
  Heading3,
  List,
  ListOrdered,
  Quote,
  Minus,
  Image as ImageIcon,
  Undo2,
  Redo2,
} from "lucide-react";
import { cn } from "@/lib/utils";

interface Props {
  editor: Editor | null;
  onPickImages: (files: File[]) => void;
}

/** Floating formatting toolbar — Apple Journal / Bear style. */
export function EditorToolbar({ editor, onPickImages }: Props) {
  const fileRef = useRef<HTMLInputElement>(null);

  if (!editor) return null;

  const btn = (
    active: boolean,
    onClick: () => void,
    icon: React.ReactNode,
    label: string,
  ) => (
    <button
      type="button"
      title={label}
      aria-label={label}
      onMouseDown={(e) => e.preventDefault()}
      onClick={onClick}
      className={cn(
        "flex h-9 w-9 items-center justify-center rounded-lg transition",
        active
          ? "bg-accent text-accent-foreground"
          : "text-muted-foreground hover:bg-muted hover:text-foreground",
      )}
    >
      {icon}
    </button>
  );

  return (
    <div className="sticky top-0 z-10 flex flex-wrap items-center gap-1 rounded-2xl border border-border/70 bg-card/80 px-2 py-1.5 shadow-sm backdrop-blur">
      {btn(
        false,
        () => editor.chain().focus().undo().run(),
        <Undo2 className="h-4 w-4" />,
        "撤销",
      )}
      {btn(
        false,
        () => editor.chain().focus().redo().run(),
        <Redo2 className="h-4 w-4" />,
        "重做",
      )}
      <Divider />
      {btn(
        editor.isActive("heading", { level: 1 }),
        () => editor.chain().focus().toggleHeading({ level: 1 }).run(),
        <Heading1 className="h-4 w-4" />,
        "标题 1",
      )}
      {btn(
        editor.isActive("heading", { level: 2 }),
        () => editor.chain().focus().toggleHeading({ level: 2 }).run(),
        <Heading2 className="h-4 w-4" />,
        "标题 2",
      )}
      {btn(
        editor.isActive("heading", { level: 3 }),
        () => editor.chain().focus().toggleHeading({ level: 3 }).run(),
        <Heading3 className="h-4 w-4" />,
        "标题 3",
      )}
      <Divider />
      {btn(
        editor.isActive("bold"),
        () => editor.chain().focus().toggleBold().run(),
        <Bold className="h-4 w-4" />,
        "粗体",
      )}
      {btn(
        editor.isActive("italic"),
        () => editor.chain().focus().toggleItalic().run(),
        <Italic className="h-4 w-4" />,
        "斜体",
      )}
      {btn(
        editor.isActive("underline"),
        () => editor.chain().focus().toggleUnderline().run(),
        <UnderlineIcon className="h-4 w-4" />,
        "下划线",
      )}
      {btn(
        editor.isActive("strike"),
        () => editor.chain().focus().toggleStrike().run(),
        <Strikethrough className="h-4 w-4" />,
        "删除线",
      )}
      <Divider />
      {btn(
        editor.isActive("bulletList"),
        () => editor.chain().focus().toggleBulletList().run(),
        <List className="h-4 w-4" />,
        "无序列表",
      )}
      {btn(
        editor.isActive("orderedList"),
        () => editor.chain().focus().toggleOrderedList().run(),
        <ListOrdered className="h-4 w-4" />,
        "有序列表",
      )}
      {btn(
        editor.isActive("blockquote"),
        () => editor.chain().focus().toggleBlockquote().run(),
        <Quote className="h-4 w-4" />,
        "引用",
      )}
      {btn(
        editor.isActive("horizontalRule"),
        () => editor.chain().focus().setHorizontalRule().run(),
        <Minus className="h-4 w-4" />,
        "分割线",
      )}
      <Divider />
      <button
        type="button"
        title="插入图片"
        aria-label="插入图片"
        onMouseDown={(e) => e.preventDefault()}
        onClick={() => fileRef.current?.click()}
        className="flex h-9 w-9 items-center justify-center rounded-lg text-muted-foreground transition hover:bg-muted hover:text-foreground"
      >
        <ImageIcon className="h-4 w-4" />
      </button>
      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={(e) => {
          const files = Array.from(e.target.files ?? []);
          if (files.length) onPickImages(files);
          e.target.value = "";
        }}
      />
    </div>
  );
}

function Divider() {
  return <span className="mx-1 h-5 w-px bg-border" />;
}
