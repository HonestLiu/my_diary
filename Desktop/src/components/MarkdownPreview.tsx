import { useMemo } from "react";
import MarkdownIt from "markdown-it";

/**
 * 与移动端 docBlocksToPreviewSpans 同构的 Markdown 预览渲染：
 * 保留行内标记（加粗/斜体/下划线/删除线/代码），忽略块级样式
 * （标题字号、列表符号、引用竖线、代码块底纹），块之间以换行分隔。
 * 输出纯 ReactNode，供 EntryCard 等 1~2 行截断的列表卡使用。
 */

const md = new MarkdownIt({ html: true, linkify: false, breaks: false });

/** markdown-it 的行内 token 类型（避免子路径类型导入）。 */
type MdToken = ReturnType<typeof md.parse>[number];

export function MarkdownPreview({
  body,
  className,
}: {
  body: string;
  className?: string;
}) {
  const nodes = useMemo(() => renderPreview(body), [body]);
  if (nodes.length === 0) return null;
  return <span className={`diary-font ${className ?? ""}`}>{nodes}</span>;
}

/** 把 Markdown 正文渲染为行内 React 节点（块与块之间以换行分隔）。 */
function renderPreview(body: string): React.ReactNode[] {
  const tokens = md.parse(body, {});
  const out: React.ReactNode[] = [];
  let first = true;

  for (const t of tokens) {
    // 跳过 media / 分割线 / 图片 / 代码块等块级内容（移动端同样忽略）。
    if (t.type === "image") continue;
    if (t.type === "hr") continue;
    if (t.type === "code_block" || t.type === "fence") {
      // 代码块：保留文字但不带底纹（移动端忽略块级样式）。
      if (t.content.trim()) {
        if (!first) out.push("\n");
        first = false;
        out.push(t.content.trim());
      }
      continue;
    }
    if (t.type === "inline") {
      const text = t.content.trim();
      if (!text) continue;
      if (!first) out.push("\n");
      first = false;
      out.push(renderInline(t.children ?? []));
    }
  }
  return out;
}

/** 渲染行内 token 序列（含嵌套标记）。 */
function renderInline(tokens: MdToken[]): React.ReactNode[] {
  const out: React.ReactNode[] = [];
  let i = 0;
  while (i < tokens.length) {
    const t = tokens[i];
    if (!t) break;
    switch (t.type) {
      case "text":
        out.push(t.content);
        i++;
        break;
      case "softbreak":
      case "hardbreak":
        out.push("\n");
        i++;
        break;
      case "code_inline":
        out.push(
          <code
            key={i}
            className="mx-0.5 rounded bg-muted px-1 py-px font-mono text-[0.92em]"
          >
            {t.content}
          </code>,
        );
        i++;
        break;
      case "strong_open": {
        const [child, next] = collectUntil(tokens, i, "strong_close");
        out.push(
          <strong key={i} className="font-semibold">
            {child}
          </strong>,
        );
        i = next;
        break;
      }
      case "em_open": {
        const [child, next] = collectUntil(tokens, i, "em_close");
        out.push(
          <em key={i} className="italic">
            {child}
          </em>,
        );
        i = next;
        break;
      }
      case "s_open": {
        const [child, next] = collectUntil(tokens, i, "s_close");
        out.push(
          <del key={i} className="line-through opacity-70">
            {child}
          </del>,
        );
        i = next;
        break;
      }
      case "link_open": {
        // 链接只保留可见文字（移动端预览不渲染链接）。
        const [child, next] = collectUntil(tokens, i, "link_close");
        out.push(<span key={i}>{child}</span>);
        i = next;
        break;
      }
      case "html_inline":
        // <u>下划线</u>（tiptap-markdown html:true 时保留）。
        if (t.content === "<u>") {
          const [child, next] = collectHtmlUnderline(tokens, i);
          out.push(
            <u key={i} className="underline underline-offset-2">
              {child}
            </u>,
          );
          i = next;
        } else {
          i++;
        }
        break;
      default:
        // 其余内联 token（如 image 已在上层过滤）直接跳过。
        i++;
    }
  }
  return out;
}

/**
 * 从 open token 的位置开始，收集直到遇到指定 close token 的嵌套行内内容，
 * 返回 [渲染后的子节点, 下一个待处理下标（close 之后）]。
 */
function collectUntil(
  tokens: MdToken[],
  openIndex: number,
  closeType: string,
): [React.ReactNode, number] {
  // 找到配对的 close 下标（同层级的第一个匹配）。
  let depth = 1;
  let i = openIndex + 1;
  while (i < tokens.length && depth > 0) {
    const t = tokens[i];
    if (!t) break;
    if (t.type === tokens[openIndex]?.type) depth++;
    else if (t.type === closeType) depth--;
    if (depth === 0) break;
    i++;
  }
  const closeIndex = depth === 0 ? i : tokens.length;
  const inner = renderInline(tokens.slice(openIndex + 1, closeIndex));
  return [inner, closeIndex + 1];
}

/** 收集 `<u>…</u>` 之间的内容（html_inline 形式）。 */
function collectHtmlUnderline(
  tokens: MdToken[],
  openIndex: number,
): [React.ReactNode, number] {
  let i = openIndex + 1;
  while (i < tokens.length) {
    const t = tokens[i];
    if (t?.type === "html_inline" && t.content === "</u>") break;
    i++;
  }
  const closeIndex = i;
  const inner = renderInline(tokens.slice(openIndex + 1, closeIndex));
  return [inner, closeIndex + 1];
}
