import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';

/// 主题：暖色「纸张」风格，与桌面端设计令牌一致。
/// 提供 6 种品牌色（accent）与 亮/暗/跟随系统三档。

const Map<AccentKey, Color> accentSeeds = {
  AccentKey.amber: Color(0xFFB45309),
  AccentKey.rose: Color(0xFFBE123C),
  AccentKey.violet: Color(0xFF7C3AED),
  AccentKey.emerald: Color(0xFF059669),
  AccentKey.sky: Color(0xFF0284C7),
  AccentKey.slate: Color(0xFF475569),
};

const Map<AccentKey, String> accentLabels = {
  AccentKey.amber: '琥珀',
  AccentKey.rose: '玫瑰',
  AccentKey.violet: '紫罗兰',
  AccentKey.emerald: '翡翠',
  AccentKey.sky: '天青',
  AccentKey.slate: '岩灰',
};

ThemeData buildTheme(ThemePreference mode, AccentKey accent) {
  final brightness = switch (mode) {
    ThemePreference.light => Brightness.light,
    ThemePreference.dark => Brightness.dark,
    ThemePreference.system => Brightness.light, // 实际由 MaterialApp.themeMode 控制
  };
  final seed = accentSeeds[accent] ?? accentSeeds[AccentKey.amber]!;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );

  final bg = brightness == Brightness.light
      ? const Color(0xFFFBF7F0) // 暖纸白
      : const Color(0xFF1B1714);
  final surface = brightness == Brightness.light
      ? const Color(0xFFFDFCFA)
      : const Color(0xFF241F1B);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      surface: surface,
    ),
    scaffoldBackgroundColor: bg,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: brightness == Brightness.light
              ? Colors.black.withOpacity(0.06)
              : Colors.white.withOpacity(0.06),
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: brightness == Brightness.light ? Colors.black87 : Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.light
          ? Colors.black.withOpacity(0.03)
          : Colors.white.withOpacity(0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: const TextStyle(fontSize: 13),
    ),
    fontFamily: 'sans',
  );
}
