import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/vault/markdown_codec.dart';

/// 取某个块内、完整覆盖 [needle] 这段文字的标记类型集合。
Set<MarkKind> marksOn(DocBlock b, String needle) {
  final start = b.text.indexOf(needle);
  expect(start, greaterThanOrEqualTo(0), reason: '块内找不到「$needle」：${b.text}');
  return marksCovering(b.marks, start, start + needle.length);
}

void main() {
  group('行内标记解码', () {
    test('加粗 / 斜体 / 删除线 / 行内代码 / 下划线', () {
      final blocks = decodeMarkdown(
        '这是**粗体**和*斜体*与~~删除~~还有`code`以及<u>下划线</u>。',
      );
      expect(blocks, hasLength(1));
      final b = blocks.single;

      // 关键：解码后的纯文本里不能残留任何 Markdown 符号。
      expect(b.text, '这是粗体和斜体与删除还有code以及下划线。');
      expect(marksOn(b, '粗体'), {MarkKind.bold});
      expect(marksOn(b, '斜体'), {MarkKind.italic});
      expect(marksOn(b, '删除'), {MarkKind.strike});
      expect(marksOn(b, 'code'), {MarkKind.code});
      expect(marksOn(b, '下划线'), {MarkKind.underline});
    });

    test('嵌套与叠加标记', () {
      final b = decodeMarkdown('**粗*粗斜*粗**').single;
      expect(b.text, '粗粗斜粗');
      expect(marksOn(b, '粗斜'), {MarkKind.bold, MarkKind.italic});
      expect(marksOn(b, '粗粗斜粗'), {MarkKind.bold});
    });

    test('下划线的 __ 写法与词内下划线', () {
      expect(decodeMarkdown('__粗__').single.text, '粗');
      expect(marksOn(decodeMarkdown('__粗__').single, '粗'), {MarkKind.bold});
      // 词内下划线不应被当作强调分隔符（对齐 prosemirror-markdown）。
      final b = decodeMarkdown('snake_case_name').single;
      expect(b.text, 'snake_case_name');
      expect(b.marks, isEmpty);
    });

    test('反斜杠转义与代码内符号原样保留', () {
      expect(decodeMarkdown(r'\*不是斜体\*').single.text, '*不是斜体*');
      final code = decodeMarkdown('`a**b**c`').single;
      expect(code.text, 'a**b**c');
      expect(marksOn(code, 'a**b**c'), {MarkKind.code});
    });
  });

  group('块级解码', () {
    test('标题 / 引用 / 列表 / 待办 / 代码块 / 分割线', () {
      final md = '''# 一级
## 二级
### 三级

> 引用一句

- 甲
- 乙

1. 壹
2. 贰

- [ ] 未完成
- [x] 已完成

```dart
void main() {}
```

---

普通段落''';
      final blocks = decodeMarkdown(md);
      final kinds = blocks.map((b) => b.kind).toList();
      expect(kinds, [
        BlockKind.heading1,
        BlockKind.heading2,
        BlockKind.heading3,
        BlockKind.quote,
        BlockKind.bullet,
        BlockKind.bullet,
        BlockKind.numbered,
        BlockKind.numbered,
        BlockKind.todo,
        BlockKind.todo,
        BlockKind.code,
        BlockKind.divider,
        BlockKind.paragraph,
      ]);
      expect(blocks[0].text, '一级');
      expect(blocks[3].text, '引用一句');
      expect(blocks[8].checked, isFalse);
      expect(blocks[9].checked, isTrue);
      expect(blocks[9].text, '已完成');
      expect(blocks[10].text, 'void main() {}');
      expect(blocks[10].language, 'dart');
    });

    test('连续非空行合并为同一段落', () {
      final blocks = decodeMarkdown('第一行\n第二行\n\n另一段');
      expect(blocks, hasLength(2));
      expect(blocks[0].text, '第一行\n第二行');
      expect(blocks[1].text, '另一段');
    });
  });

  group('媒体序列化 —— 必须与桌面端逐字对齐', () {
    test('图片：![alt](path "width=N")', () {
      final blocks = decodeMarkdown('![风景](assets/images/a.webp "width=480")');
      expect(blocks, hasLength(1));
      final m = blocks.single.media!;
      expect(blocks.single.kind, BlockKind.media);
      expect(m.kind, AssetKind.image);
      expect(m.src, 'assets/images/a.webp');
      expect(m.alt, '风景');
      expect(m.width, 480);

      // 回写形态必须与桌面端 ResolvedImage.addStorage 完全一致。
      expect(encodeMarkdown(blocks), '![风景](assets/images/a.webp "width=480")');
    });

    test('图片无宽度时不写 title', () {
      final md = '![](assets/images/b.png)';
      expect(encodeMarkdown(decodeMarkdown(md)), md);
    });

    test('附件：<attachment data-…>（音频 / 视频 / 文件）', () {
      const md =
          '<attachment data-src="assets/audio/v.m4a" data-name="录音.m4a" '
          'data-kind="audio" data-size="20480"></attachment>';
      final blocks = decodeMarkdown(md);
      expect(blocks, hasLength(1));
      final m = blocks.single.media!;
      expect(m.kind, AssetKind.audio);
      expect(m.src, 'assets/audio/v.m4a');
      expect(m.name, '录音.m4a');
      expect(m.size, 20480);
      expect(encodeMarkdown(blocks), md);
    });

    test('视频带 data-width 往返', () {
      const md =
          '<attachment data-src="assets/video/c.mp4" data-name="clip.mp4" '
          'data-kind="video" data-size="1024" data-width="320"></attachment>';
      final m = decodeMarkdown(md).single.media!;
      expect(m.kind, AssetKind.video);
      expect(m.width, 320);
      expect(encodeMarkdown(decodeMarkdown(md)), md);
    });

    test('collectAssets 按出现顺序去重', () {
      final blocks = decodeMarkdown('''![](assets/images/a.png)

![](assets/images/b.png)

![](assets/images/a.png)''');
      final assets = collectAssets(blocks);
      expect(assets.map((a) => a.path).toList(),
          ['assets/images/a.png', 'assets/images/b.png']);
    });
  });

  group('往返一致性', () {
    test('富文本 + 媒体混排 encode∘decode 稳定', () {
      const md = '''# 今天

这是**粗体**、*斜体*、<u>下划线</u>与~~删除线~~，还有`inline`。

> 一句引用

- 列表甲
- 列表乙

1. 壹
2. 贰

- [x] 做完了
- [ ] 还没做

![图](assets/images/a.webp "width=600")

<attachment data-src="assets/audio/b.m4a" data-name="b.m4a" data-kind="audio" data-size="99"></attachment>

---

```js
const a = 1;
```''';
      final once = encodeMarkdown(decodeMarkdown(md));
      final twice = encodeMarkdown(decodeMarkdown(once));
      expect(once, md);
      expect(twice, once);
    });

    test('相邻同标记段不产生 **a****b**', () {
      final b = DocBlock.paragraph('ab', const [
        InlineMark(MarkKind.bold, 0, 1),
        InlineMark(MarkKind.bold, 1, 2),
      ]);
      expect(encodeMarkdown([b]), '**ab**');
    });

    test('标记首尾空白挪到符号外侧', () {
      final b = DocBlock.paragraph('a b c', const [
        InlineMark(MarkKind.bold, 1, 4), // " b "
      ]);
      final md = encodeMarkdown([b]);
      expect(md, 'a **b** c');
      expect(decodeMarkdown(md).single.text, 'a b c');
    });

    test('特殊字符被转义且解码后还原', () {
      final b = DocBlock.paragraph('价格 * 2 _ 3 ~ 4 `5` <tag>');
      final md = encodeMarkdown([b]);
      expect(decodeMarkdown(md).single.text, '价格 * 2 _ 3 ~ 4 `5` <tag>');
    });
  });

  group('decodeEntryBody 历史资产迁移', () {
    test('frontmatter 里有、正文没引用的资产补到末尾', () {
      const body = '只有文字，没有插图。';
      const assets = [
        AssetRef(kind: AssetKind.image, path: 'assets/images/old.jpg',
            name: 'old.jpg', size: 123),
        AssetRef(kind: AssetKind.audio, path: 'assets/audio/old.m4a'),
      ];
      final blocks = decodeEntryBody(body, assets);
      expect(blocks.first.kind, BlockKind.paragraph);
      final media = blocks.where((b) => b.kind == BlockKind.media).toList();
      expect(media, hasLength(2));
      expect(media[0].media!.src, 'assets/images/old.jpg');
      expect(media[1].media!.kind, AssetKind.audio);

      // 迁移后再保存，资产清单不丢。
      expect(collectAssets(blocks).map((a) => a.path).toList(),
          ['assets/images/old.jpg', 'assets/audio/old.m4a']);
    });

    test('正文已引用的资产不重复追加', () {
      const body = '![](assets/images/a.png)';
      const assets = [
        AssetRef(kind: AssetKind.image, path: 'assets/images/a.png'),
      ];
      final blocks = decodeEntryBody(body, assets);
      expect(blocks.where((b) => b.kind == BlockKind.media), hasLength(1));
    });

    test('空正文空资产 → 空文档', () {
      expect(decodeEntryBody('', const []), isEmpty);
    });
  });

  group('与 vault 落盘层的联动', () {
    // vault 会在文件顶部额外写一行 `# <标题>` 便于人类阅读，读回时剥离第一行 H1。
    // 编辑器允许用户在正文首块就放一个一级标题 —— 必须确认它不会被那条规则吃掉。
    JournalEntry entryWith(String body) => JournalEntry(
          id: 'e1',
          date: '2026-08-17',
          title: '标题',
          mood: Mood.neutral,
          weather: Weather.unknown,
          tags: const [],
          assets: const [],
          createdAt: '2026-08-17T00:00:00.000Z',
          updatedAt: '2026-08-17T00:00:00.000Z',
          body: body,
        );

    test('正文首块是一级标题时不会被标题行吞掉', () {
      final body = encodeMarkdown([
        DocBlock(kind: BlockKind.heading1, text: '用户自己的一级标题'),
        DocBlock.paragraph('正文'),
      ]);
      final roundTripped =
          parseEntryFile(serializeEntryFile(entryWith(body))).body;
      expect(roundTripped, body);
      expect(decodeMarkdown(roundTripped).first.kind, BlockKind.heading1);
    });

    test('富文本 + 媒体正文经落盘往返逐字不变', () {
      final body = encodeMarkdown([
        DocBlock.paragraph('带**样式**的一段', const [InlineMark(MarkKind.bold, 1, 3)]),
        DocBlock.media(const MediaPayload(
          kind: AssetKind.image,
          src: 'assets/images/a.webp',
          width: 480,
        )),
        DocBlock.media(const MediaPayload(
          kind: AssetKind.video,
          src: 'assets/video/b.mp4',
          name: 'b.mp4',
          size: 2048,
        )),
        DocBlock(kind: BlockKind.todo, text: '记得导出', checked: true),
      ]);
      expect(parseEntryFile(serializeEntryFile(entryWith(body))).body, body);
    });
  });

  group('标记区间运算', () {
    test('normalizeMarks 裁剪越界、丢空区间并合并同类', () {
      final marks = normalizeMarks(const [
        InlineMark(MarkKind.bold, -3, 2), // 起点裁到 0
        InlineMark(MarkKind.bold, 2, 4), // 与上一段相邻 → 合并
        InlineMark(MarkKind.italic, 8, 99), // 整段越界 → 丢弃
        InlineMark(MarkKind.bold, 1, 1), // 空区间 → 丢弃
      ], 5);
      expect(marks, const [InlineMark(MarkKind.bold, 0, 4)]);
    });

    test('applyMark / removeMark 打洞', () {
      var marks = applyMark(const [], MarkKind.bold, 0, 4, textLength: 10);
      expect(marks, const [InlineMark(MarkKind.bold, 0, 4)]);
      marks = removeMark(marks, MarkKind.bold, 1, 2, textLength: 10);
      expect(marks, const [
        InlineMark(MarkKind.bold, 0, 1),
        InlineMark(MarkKind.bold, 2, 4),
      ]);
    });

    test('computeTextDiff 定位最小差异', () {
      final d = computeTextDiff('abcdef', 'abXcdef');
      expect(d.at, 2);
      expect(d.removed, 0);
      expect(d.inserted, 1);

      final del = computeTextDiff('abcdef', 'abef');
      expect(del.at, 2);
      expect(del.removed, 2);
      expect(del.inserted, 0);
    });

    test('shiftMarks：区间内插入延续样式，右端外插入默认不延续', () {
      expect(
        shiftMarks(const [InlineMark(MarkKind.bold, 0, 3)],
            at: 1, removed: 0, inserted: 2, textLength: 5),
        const [InlineMark(MarkKind.bold, 0, 5)],
      );
      // 紧贴右端输入：不传 extend → 保持原长度
      expect(
        shiftMarks(const [InlineMark(MarkKind.bold, 0, 3)],
            at: 3, removed: 0, inserted: 2, textLength: 5),
        const [InlineMark(MarkKind.bold, 0, 3)],
      );
      // 传 extend → 样式延续到新输入的字符（工具栏「继续加粗」行为）
      expect(
        shiftMarks(const [InlineMark(MarkKind.bold, 0, 3)],
            at: 3,
            removed: 0,
            inserted: 2,
            textLength: 5,
            extend: {MarkKind.bold}),
        const [InlineMark(MarkKind.bold, 0, 5)],
      );
    });

    test('marksAt 紧贴区间右端时仍生效', () {
      const marks = [InlineMark(MarkKind.bold, 1, 3)];
      expect(marksAt(marks, 0), isEmpty);
      expect(marksAt(marks, 2), {MarkKind.bold});
      expect(marksAt(marks, 3), {MarkKind.bold});
      expect(marksAt(marks, 4), isEmpty);
    });

    test('splitMarks 拆块时切分区间', () {
      final parts = splitMarks(const [InlineMark(MarkKind.bold, 1, 5)], 3);
      expect(parts.head, const [InlineMark(MarkKind.bold, 1, 3)]);
      expect(parts.tail, const [InlineMark(MarkKind.bold, 0, 2)]);
    });
  });
}
