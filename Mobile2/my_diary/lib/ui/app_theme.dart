import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';

/// 设计系统：现代极简 · 中性。
/// 中性灰白底 + 单一强调色 + 细分割线 + 统一圆角，亮/暗双档。
/// 强调色沿用桌面端品牌色（accent），其余一律中性，保证「商用软件」的干净专业感。

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

/// 跨屏统一的设计令牌，挂在 Theme 扩展上。
class AppTokens extends ThemeExtension<AppTokens> {
  final Color surfaceVariant;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color fill; // 输入框/芯片的浅填充
  final double radiusCard;
  final double radiusInput;
  final double radiusChip;
  final double radiusSheet;

  const AppTokens({
    required this.surfaceVariant,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.fill,
    required this.radiusCard,
    required this.radiusInput,
    required this.radiusChip,
    required this.radiusSheet,
  });

  @override
  AppTokens copyWith({
    Color? surfaceVariant,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? fill,
    double? radiusCard,
    double? radiusInput,
    double? radiusChip,
    double? radiusSheet,
  }) =>
      AppTokens(
        surfaceVariant: surfaceVariant ?? this.surfaceVariant,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        fill: fill ?? this.fill,
        radiusCard: radiusCard ?? this.radiusCard,
        radiusInput: radiusInput ?? this.radiusInput,
        radiusChip: radiusChip ?? this.radiusChip,
        radiusSheet: radiusSheet ?? this.radiusSheet,
      );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      radiusCard: radiusCard,
      radiusInput: radiusInput,
      radiusChip: radiusChip,
      radiusSheet: radiusSheet,
    );
  }
}

extension AppTokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;

  TextStyle get titleLarge =>
      tt.titleLarge!.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w700);
  TextStyle get titleMedium =>
      tt.titleMedium!.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w600);
  TextStyle get bodyText => tt.bodyMedium!.copyWith(color: tokens.textPrimary);
  TextStyle get caption =>
      tt.bodySmall!.copyWith(color: tokens.textSecondary);
}

ThemeData buildTheme(ThemePreference mode, AccentKey accent, FontKey font) {
  final brightness = switch (mode) {
    ThemePreference.light => Brightness.light,
    ThemePreference.dark => Brightness.dark,
    ThemePreference.system => Brightness.light, // 实际由 MaterialApp.themeMode 控制
  };
  final seed = accentSeeds[accent] ?? accentSeeds[AccentKey.amber]!;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  final isLight = brightness == Brightness.light;
  final bg = isLight ? const Color(0xFFF6F7F9) : const Color(0xFF0E0F12);
  final surface = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF17191E);
  final surfaceVariant =
      isLight ? const Color(0xFFF1F3F5) : const Color(0xFF1F222A);
  final border =
      isLight ? const Color(0xFFE6E8EB) : const Color(0xFF272A31);
  final textPrimary =
      isLight ? const Color(0xFF101828) : const Color(0xFFF2F4F7);
  final textSecondary =
      isLight ? const Color(0xFF667085) : const Color(0xFF98A2B3);
  final textTertiary =
      isLight ? const Color(0xFF98A2B3) : const Color(0xFF6B7280);
  final fill =
      isLight ? const Color(0xFFF2F4F7) : const Color(0xFF20232B);

  final tokens = AppTokens(
    surfaceVariant: surfaceVariant,
    border: border,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    fill: fill,
    radiusCard: 16,
    radiusInput: 12,
    radiusChip: 20,
    radiusSheet: 24,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: font == FontKey.serif ? 'serif' : null,
    colorScheme: scheme.copyWith(surface: surface, onSurface: textPrimary),
    scaffoldBackgroundColor: bg,
    extensions: <ThemeExtension<dynamic>>[tokens],
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusCard),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: textPrimary,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      // 不覆盖 shape：默认 extended 为胶囊（StadiumBorder）、圆形 FAB 为圆。
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusInput),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusInput),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusInput),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: textTertiary),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusChip)),
      labelStyle: const TextStyle(fontSize: 13),
      backgroundColor: fill,
      side: BorderSide(color: border),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: textSecondary,
      titleTextStyle: TextStyle(fontSize: 15, color: textPrimary),
      subtitleTextStyle: TextStyle(fontSize: 13, color: textSecondary),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      selectedItemColor: scheme.primary,
      unselectedItemColor: textTertiary,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      landscapeLayout: BottomNavigationBarLandscapeLayout.spread,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusInput),
        side: BorderSide(color: border),
      ),
    ),
  );
}
