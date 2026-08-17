// Regression: memory-card preview must show *rendered* markdown, not raw source.
// Pins the exact pipeline the memory card uses:
//   docBlocksToPreviewSpans(context, decodeEntryBody(body, assets), baseStyle)
// so inline marks survive as styles, block syntax/media get flattened away.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_diary_mobile/editor/doc_view.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';

void main() {
  testWidgets('memory preview flattens markdown into styled spans',
      (WidgetTester tester) async {
    const tokens = AppTokens(
      surfaceVariant: Color(0xFFF1F3F5),
      border: Color(0xFFE6E8EB),
      textPrimary: Color(0xFF101828),
      textSecondary: Color(0xFF667085),
      textTertiary: Color(0xFF98A2B3),
      fill: Color(0xFFF2F4F7),
      radiusCard: 16,
      radiusInput: 12,
      radiusChip: 20,
      radiusSheet: 24,
    );
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.amber,
        brightness: Brightness.light,
      ),
    ).copyWith(extensions: <ThemeExtension<dynamic>>[tokens]);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(builder: (context) {
            final entry = JournalEntry(
              id: 'a1',
              date: '2026-08-17',
              title: '标题',
              mood: Mood.happy,
              weather: Weather.sunny,
              tags: const [],
              assets: const [
                AssetRef(
                  kind: AssetKind.image,
                  path: 'assets/images/x.webp',
                  name: 'x.webp',
                  size: 1,
                ),
              ],
              createdAt: '2026-08-17T10:00:00.000Z',
              updatedAt: '2026-08-17T10:00:00.000Z',
              body: '今天写了 **加粗** 和 *斜体*，还有 `code`。\n\n'
                  '- 列表项一\n\n'
                  '![图](assets/images/x.webp)',
            );

            final spans = docBlocksToPreviewSpans(
              context,
              decodeEntryBody(entry.body, entry.assets),
              baseStyle: const TextStyle(fontSize: 12),
            );
            final plain = TextSpan(children: spans).toPlainText();

            // 纯文本里不再有 Markdown 记号 / 图片语法。
            expect(plain, isNot(contains('**')));
            expect(plain, isNot(contains('*')));
            expect(plain, isNot(contains('!')));
            expect(plain, isNot(contains('x.webp')));
            // 正文文字保留；列表块级符号不展开，但内容在。
            expect(plain, contains('加粗'));
            expect(plain, contains('斜体'));
            expect(plain, contains('code'));
            expect(plain, contains('列表项一'));

            // 行内标记落地为样式：加粗 span 带 FontWeight.w700。
            final bold = spans
                .whereType<TextSpan>()
                .where((s) =>
                    s.text == '加粗' && s.style?.fontWeight == FontWeight.w700)
                .toList();
            expect(bold, isNotEmpty);
            // 代码 span 落到等宽字体。
            final code = spans
                .whereType<TextSpan>()
                .where((s) =>
                    s.text == 'code' && s.style?.fontFamily == 'monospace')
                .toList();
            expect(code, isNotEmpty);

            return const SizedBox.shrink();
          }),
        ),
      ),
    );
  });
}
