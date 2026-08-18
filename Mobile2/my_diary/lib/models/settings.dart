import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/sync_types.dart';

/// 磁盘上的 settings.json（用户偏好，非日记内容）。
/// 与桌面端 `Desktop/src/types/journal.ts` 的 AppSettings 一致。
class AppSettings {
  final int version;
  final ThemePreference theme;
  final AccentKey accent;
  final FontKey font;
  final String displayName;
  final int weekStartsOn; // 0 = 周日, 1 = 周一
  final Mood defaultMood;
  final SyncConfig sync;
  final bool autoLocateNew; // 新建日记时自动定位填充位置与天气
  final bool showDetailMap; // 日记预览页是否显示地图块

  const AppSettings({
    this.version = 1,
    this.theme = ThemePreference.light,
    this.accent = AccentKey.amber,
    this.font = FontKey.sans,
    this.displayName = '',
    this.weekStartsOn = 1,
    this.defaultMood = Mood.neutral,
    this.sync = const SyncConfig(),
    this.autoLocateNew = false,
    this.showDetailMap = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final themeStr = json['theme'] as String?;
    final accentStr = json['accent'] as String?;
    final fontStr = json['font'] as String?;
    final defaultMoodStr = json['defaultMood'] as String?;
    final syncJson = json['sync'] as Map<String, dynamic>?;
    return AppSettings(
      version: json['version'] as int? ?? 1,
      theme: ThemePreference.values.asNameMap()[themeStr] ??
          ThemePreference.light,
      accent:
          AccentKey.values.asNameMap()[accentStr] ?? AccentKey.amber,
      font: FontKey.values.asNameMap()[fontStr] ?? FontKey.sans,
      displayName: (json['displayName'] as String?) ?? '',
      weekStartsOn: (json['weekStartsOn'] as int?) ?? 1,
      defaultMood: Mood.parse(defaultMoodStr),
      sync: syncJson != null
          ? SyncConfig.fromJson(syncJson)
          : const SyncConfig(),
      autoLocateNew: json['autoLocateNew'] as bool? ?? false,
      showDetailMap: json['showDetailMap'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'theme': theme.name,
        'accent': accent.name,
        'font': font.name,
        'displayName': displayName,
        'weekStartsOn': weekStartsOn,
        'defaultMood': defaultMood.name,
        'sync': sync.toJson(),
        'autoLocateNew': autoLocateNew,
        'showDetailMap': showDetailMap,
      };

  AppSettings copyWith({
    ThemePreference? theme,
    AccentKey? accent,
    FontKey? font,
    String? displayName,
    int? weekStartsOn,
    Mood? defaultMood,
    SyncConfig? sync,
    bool? autoLocateNew,
    bool? showDetailMap,
  }) =>
      AppSettings(
        version: version,
        theme: theme ?? this.theme,
        accent: accent ?? this.accent,
        font: font ?? this.font,
        displayName: displayName ?? this.displayName,
        weekStartsOn: weekStartsOn ?? this.weekStartsOn,
        defaultMood: defaultMood ?? this.defaultMood,
        sync: sync ?? this.sync,
        autoLocateNew: autoLocateNew ?? this.autoLocateNew,
        showDetailMap: showDetailMap ?? this.showDetailMap,
      );
}

/// 默认设置（空 vault 时使用）。
const AppSettings defaultSettings = AppSettings();
