import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/editor/rich_text_controller.dart';

const sentinel = RichTextController.sentinel;

/// 模拟软键盘输入：直接把新的 TextEditingValue 推给控制器。
void type(RichTextController c, String plain, int caret) {
  c.value = TextEditingValue(
    text: sentinel + plain,
    selection: TextSelection.collapsed(offset: caret + 1),
  );
}

/// 模拟「在纯文本行首按退格」：软键盘会把零宽哨兵删掉。
void backspaceAtLineStart(RichTextController c) {
  c.value = TextEditingValue(
    text: c.plainText,
    selection: const TextSelection.collapsed(offset: 0),
  );
}

void main() {
  test('哨兵对上层透明：plainText 不含哨兵，实际文本含哨兵', () {
    final c = RichTextController(text: 'abc');
    expect(c.text, '${sentinel}abc');
    expect(c.plainText, 'abc');
    expect(c.offsetBase, 1);
  });

  test('行首退格触发块合并，且内容与标记不被破坏', () {
    var merged = 0;
    final c = RichTextController(
      text: 'abc',
      marks: const [InlineMark(MarkKind.bold, 0, 3)],
    );
    c.onMergeBackward = () => merged++;

    backspaceAtLineStart(c);

    expect(merged, 1, reason: '删掉哨兵且内容未变 → 判定为行首退格');
    expect(c.plainText, 'abc', reason: '内容不能被吞掉');
    expect(c.text.startsWith(sentinel), isTrue, reason: '哨兵必须被补回');
    expect(c.marks, const [InlineMark(MarkKind.bold, 0, 3)]);
  });

  test('哨兵连同内容一起被删（全选删除）不触发合并', () {
    var merged = 0;
    final c = RichTextController(text: 'abc');
    c.onMergeBackward = () => merged++;

    c.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );

    expect(merged, 0);
    expect(c.plainText, '');
    expect(c.text, sentinel);
  });

  test('光标永远不会落到哨兵之前', () {
    final c = RichTextController(text: 'abc');
    c.selection = const TextSelection.collapsed(offset: 0);
    expect(c.selection.baseOffset, 1);

    c.setPlainCaret(0);
    expect(c.selection.baseOffset, 1);
    c.setPlainCaret(99);
    expect(c.selection.baseOffset, 4, reason: '越界应夹到文本末尾');
  });

  test('在样式区间右端继续输入 → 样式延续', () {
    final c = RichTextController(
      text: 'abc',
      marks: const [InlineMark(MarkKind.bold, 0, 3)],
    );
    type(c, 'abcd', 4);
    expect(c.plainText, 'abcd');
    expect(c.marks, const [InlineMark(MarkKind.bold, 0, 4)]);
  });

  test('在样式区间之外输入 → 不染上样式', () {
    final c = RichTextController(
      text: 'ab cd',
      marks: const [InlineMark(MarkKind.bold, 0, 2)],
    );
    type(c, 'ab cdX', 6);
    expect(c.marks, const [InlineMark(MarkKind.bold, 0, 2)]);
  });

  test('删除文本时标记区间随之收缩', () {
    final c = RichTextController(
      text: 'abcdef',
      marks: const [InlineMark(MarkKind.bold, 1, 5)],
    );
    type(c, 'abef', 2); // 删掉 "cd"
    expect(c.plainText, 'abef');
    expect(c.marks, const [InlineMark(MarkKind.bold, 1, 3)]);
  });

  test('折叠光标下 toggleMark 只影响后续输入', () {
    final c = RichTextController(text: 'ab');
    c.setPlainCaret(2);
    c.toggleMark(MarkKind.bold);

    expect(c.activeMarks, {MarkKind.bold}, reason: '待生效样式要能回显到工具栏');
    expect(c.marks, isEmpty, reason: '还没输入，不该产生区间');

    type(c, 'abc', 3);
    expect(c.marks, const [InlineMark(MarkKind.bold, 2, 3)]);
  });

  test('折叠光标下关闭已生效样式 → 后续输入不再加粗', () {
    final c = RichTextController(
      text: 'abc',
      marks: const [InlineMark(MarkKind.bold, 0, 3)],
    );
    c.setPlainCaret(3);
    expect(c.activeMarks, {MarkKind.bold});

    c.toggleMark(MarkKind.bold); // 关掉
    expect(c.activeMarks, isEmpty);

    type(c, 'abcd', 4);
    expect(c.marks, const [InlineMark(MarkKind.bold, 0, 3)],
        reason: '新输入的 d 不该被加粗');
  });

  test('有选区时 toggleMark 作用于选区，可二次点击取消', () {
    var docChanges = 0;
    final c = RichTextController(text: 'hello');
    c.onDocChanged = (_, _) => docChanges++;

    // 选中 plain [0,5)
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 6);
    c.toggleMark(MarkKind.italic);
    expect(c.marks, const [InlineMark(MarkKind.italic, 0, 5)]);

    c.toggleMark(MarkKind.italic);
    expect(c.marks, isEmpty);
    expect(docChanges, 2);
  });

  test('activeMarks 在部分覆盖的选区上不生效', () {
    final c = RichTextController(
      text: 'hello',
      marks: const [InlineMark(MarkKind.bold, 0, 2)],
    );
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 6);
    expect(c.activeMarks, isEmpty, reason: '只覆盖一部分 → 工具栏不该高亮');

    c.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    expect(c.activeMarks, {MarkKind.bold});
  });

  test('clearMarks 清空样式并通知', () {
    String? lastText;
    List<InlineMark>? lastMarks;
    final c = RichTextController(
      text: 'abc',
      marks: const [InlineMark(MarkKind.bold, 0, 3)],
    );
    c.onDocChanged = (t, m) {
      lastText = t;
      lastMarks = m;
    };
    c.clearMarks();
    expect(c.marks, isEmpty);
    expect(lastText, 'abc');
    expect(lastMarks, isEmpty);
  });

  test('setDoc 重置内容 / 标记 / 光标，且不回调 onDocChanged', () {
    var docChanges = 0;
    final c = RichTextController(text: 'abc');
    c.onDocChanged = (_, _) => docChanges++;

    c.setDoc('xyz', const [InlineMark(MarkKind.italic, 0, 3)], caret: 1);

    expect(c.plainText, 'xyz');
    expect(c.marks, const [InlineMark(MarkKind.italic, 0, 3)]);
    expect(c.selection.baseOffset, 2, reason: 'caret=1 → 含哨兵偏移为 2');
    expect(docChanges, 0, reason: '外部驱动的重置不应再回调，避免与 setState 打环');
  });

  test('onDocChanged 汇报的是纯文本', () {
    final seen = <String>[];
    final c = RichTextController(text: 'a');
    c.onDocChanged = (t, _) => seen.add(t);
    type(c, 'ab', 2);
    type(c, 'abc', 3);
    expect(seen, ['ab', 'abc']);
    expect(seen.every((s) => !s.contains(sentinel)), isTrue);
  });

  testWidgets('buildTextSpan 拼出的文本与实际文本逐字相等（否则光标会错位）',
      (tester) async {
    final c = RichTextController(
      text: '这是粗体和斜体',
      marks: const [
        InlineMark(MarkKind.bold, 2, 4),
        InlineMark(MarkKind.italic, 5, 7),
      ],
    );

    late BuildContext ctx;
    await tester.pumpWidget(Builder(builder: (context) {
      ctx = context;
      return const SizedBox.shrink();
    }));

    final span = c.buildTextSpan(context: ctx, withComposing: false);
    expect(span.toPlainText(), c.text);

    // 样式确实分段了：哨兵 + 3 段（普通/粗/普通/斜…）
    expect(span.children!.length, greaterThan(2));
  });
}
