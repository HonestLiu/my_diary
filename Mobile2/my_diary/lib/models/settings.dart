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
  final String motto; // 座右铭（个人主页展示）
  final String avatar; // 头像文件名（应用文档目录下；空 = 未设置）
  final int weekStartsOn; // 0 = 周日, 1 = 周一
  final Mood defaultMood;
  final SyncConfig sync;
  final bool autoLocateNew; // 新建日记时自动定位填充位置与天气
  final bool showDetailMap; // 日记预览页是否显示地图块
  // 上传压缩质量（1–100，越高越清晰、文件越大；100 = 不压缩）。
  final int imageCompressQuality; // 图片
  final int videoCompressQuality; // 视频

  const AppSettings({
    this.version = 1,
    this.theme = ThemePreference.light,
    this.accent = AccentKey.sky,
    this.font = FontKey.sans,
    this.displayName = '',
    this.motto = '',
    this.avatar = '',
    this.weekStartsOn = 1,
    this.defaultMood = Mood.neutral,
    this.sync = const SyncConfig(),
    this.autoLocateNew = false,
    this.showDetailMap = true,
    this.imageCompressQuality = 80,
    this.videoCompressQuality = 60,
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
          AccentKey.values.asNameMap()[accentStr] ?? AccentKey.sky,
      font: FontKey.values.asNameMap()[fontStr] ?? FontKey.sans,
      displayName: (json['displayName'] as String?) ?? '',
      motto: (json['motto'] as String?) ?? '',
      avatar: (json['avatar'] as String?) ?? '',
      weekStartsOn: (json['weekStartsOn'] as int?) ?? 1,
      defaultMood: Mood.parse(defaultMoodStr),
      sync: syncJson != null
          ? SyncConfig.fromJson(syncJson)
          : const SyncConfig(),
      autoLocateNew: json['autoLocateNew'] as bool? ?? false,
      showDetailMap: json['showDetailMap'] as bool? ?? true,
      imageCompressQuality:
          ((json['imageCompressQuality'] as int? ?? 80).clamp(1, 100)).toInt(),
      videoCompressQuality:
          ((json['videoCompressQuality'] as int? ?? 60).clamp(1, 100)).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'theme': theme.name,
        'accent': accent.name,
        'font': font.name,
        'displayName': displayName,
        'motto': motto,
        'avatar': avatar,
        'weekStartsOn': weekStartsOn,
        'defaultMood': defaultMood.name,
        'sync': sync.toJson(),
        'autoLocateNew': autoLocateNew,
        'showDetailMap': showDetailMap,
        'imageCompressQuality': imageCompressQuality,
        'videoCompressQuality': videoCompressQuality,
      };

  AppSettings copyWith({
    ThemePreference? theme,
    AccentKey? accent,
    FontKey? font,
    String? displayName,
    String? motto,
    String? avatar,
    int? weekStartsOn,
    Mood? defaultMood,
    SyncConfig? sync,
    bool? autoLocateNew,
    bool? showDetailMap,
    int? imageCompressQuality,
    int? videoCompressQuality,
  }) =>
      AppSettings(
        version: version,
        theme: theme ?? this.theme,
        accent: accent ?? this.accent,
        font: font ?? this.font,
        displayName: displayName ?? this.displayName,
        motto: motto ?? this.motto,
        avatar: avatar ?? this.avatar,
        weekStartsOn: weekStartsOn ?? this.weekStartsOn,
        defaultMood: defaultMood ?? this.defaultMood,
        sync: sync ?? this.sync,
        autoLocateNew: autoLocateNew ?? this.autoLocateNew,
        showDetailMap: showDetailMap ?? this.showDetailMap,
        imageCompressQuality:
            imageCompressQuality ?? this.imageCompressQuality,
        videoCompressQuality:
            videoCompressQuality ?? this.videoCompressQuality,
      );
}

/// 默认设置（空 vault 时使用）。
const AppSettings defaultSettings = AppSettings();
