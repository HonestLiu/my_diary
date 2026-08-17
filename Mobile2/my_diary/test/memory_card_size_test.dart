// Empirical measurement: does a 145x145 SizedBox inside a horizontal ListView
// actually render as a square? This isolates the layout, not the real widget.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:my_diary_mobile/ui/app_theme.dart';

void main() {
  testWidgets('memory card SizedBox(145x145) renders as a square',
      (WidgetTester tester) async {
    await initializeDateFormatting('zh_CN', '');

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
          body: SizedBox(
            height: 145,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                KeyedSubtree(
                  key: const Key('card'),
                  child: SizedBox(
                    width: 145,
                    height: 145,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              tokens.surfaceVariant,
                              Color.alphaBlend(
                                Colors.amber.withValues(alpha: 0.22),
                                tokens.surfaceVariant,
                              ),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            const Positioned(
                              right: -6,
                              top: -14,
                              child: Text('忆',
                                  style: TextStyle(
                                      fontSize: 92,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.amber)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: tokens.fill,
                                      borderRadius:
                                          BorderRadius.circular(tokens.radiusChip),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.auto_awesome_outlined,
                                            size: 12, color: Colors.amber),
                                        SizedBox(width: 4),
                                        Text('5月',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.amber)),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text('2026年5月3日 · 星期日',
                                      style: TextStyle(
                                          color: tokens.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 3),
                                  Text('那天的午后',
                                      style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 3),
                                  Text('一些回忆的文字预览内容。',
                                      style: TextStyle(
                                          color: tokens.textSecondary,
                                          fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(const Key('card')));
    debugPrint('>>> MEASURED CARD SIZE: ${size.width} x ${size.height}');
    expect(size.width, 145);
    expect(size.height, 145);
  });
}
