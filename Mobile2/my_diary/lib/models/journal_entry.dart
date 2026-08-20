/// 核心领域模型 —— 与桌面端 `Desktop/src/types/journal.ts` 保持一致。
///
/// 设计原则：磁盘上的 Markdown 文件是「单一事实来源」。
/// 这里的所有类型都镜像落盘 frontmatter + 正文的内容。

/// 心情。顺序与桌面端一致（用于选择器展示）。
library;

import "package:flutter/material.dart";

enum Mood {
  happy,
  excited,
  calm,
  neutral,
  tired,
  sad,
  angry;

  static const List<Mood> ordered = [
    Mood.happy,
    Mood.excited,
    Mood.calm,
    Mood.neutral,
    Mood.tired,
    Mood.sad,
    Mood.angry,
  ];

  String get value => name;

  static Mood parse(String? v) =>
      Mood.values.asNameMap()[v] ?? Mood.neutral;

  /// 中文标签，用于 UI 展示。
  String get label {
    switch (this) {
      case Mood.happy:
        return '开心';
      case Mood.excited:
        return '兴奋';
      case Mood.calm:
        return '平静';
      case Mood.neutral:
        return '一般';
      case Mood.tired:
        return '疲惫';
      case Mood.sad:
        return '难过';
      case Mood.angry:
        return '生气';
    }
  }

  /// 用于展示的 emoji。
  String get emoji {
    switch (this) {
      case Mood.happy:
        return '😄';
      case Mood.excited:
        return '🤩';
      case Mood.calm:
        return '😌';
      case Mood.neutral:
        return '😐';
      case Mood.tired:
        return '😴';
      case Mood.sad:
        return '😢';
      case Mood.angry:
        return '😠';
    }
  }

  // ---- 自定义 iconfont 表情（font-family: moodfont） ---------------------
  // 矢量、随主题色、任意大小。Mood.emoji 保留作为文本场景（如选择器、
  // 无图标字体时的兜底），UI 展示默认走 iconData / iconChar。
  static const _moodfontFamily = 'moodfont';

  /// 用于 [Icon] widget：呈现自定义心情表情（透明矢量，色随主题）。
  /// 注意：codepoint 必须是编译期常量（字面量），否则 release 构建的
  /// tree-shake-icons 无法静态分析而报错。
  IconData get iconData => switch (this) {
        Mood.happy => const IconData(0xe61f, fontFamily: _moodfontFamily),
        Mood.excited => const IconData(0xe613, fontFamily: _moodfontFamily),
        Mood.calm => const IconData(0xe616, fontFamily: _moodfontFamily),
        Mood.neutral => const IconData(0xe621, fontFamily: _moodfontFamily),
        Mood.tired => const IconData(0xe614, fontFamily: _moodfontFamily),
        Mood.sad => const IconData(0xe603, fontFamily: _moodfontFamily),
        Mood.angry => const IconData(0xe61e, fontFamily: _moodfontFamily),
      };

  /// 用于 [Text] / [TextSpan]（混排场景）：在 `fontFamily: moodfont`
  /// 样式下渲染表情字符。
  String get iconChar => String.fromCharCode(_iconCode);

  int get _iconCode {
    switch (this) {
      case Mood.happy:
        return 0xe61f; // kaixin 开心
      case Mood.excited:
        return 0xe613; // ziyaxiao 龇牙笑（兴奋）
      case Mood.calm:
        return 0xe616; // huiqi 呼气（平静）
      case Mood.neutral:
        return 0xe621; // wubiaoqing 无表情
      case Mood.tired:
        return 0xe614; // liuhan 流汗（疲惫）
      case Mood.sad:
        return 0xe603; // nanguo 难过
      case Mood.angry:
        return 0xe61e; // fanu 发怒
    }
  }
}

enum Weather {
  sunny,
  cloudy,
  rainy,
  snowy,
  foggy,
  windy,
  unknown;

  static const List<Weather> ordered = [
    Weather.sunny,
    Weather.cloudy,
    Weather.rainy,
    Weather.snowy,
    Weather.foggy,
    Weather.windy,
    Weather.unknown,
  ];

  String get value => name;

  static Weather parse(String? v) =>
      Weather.values.asNameMap()[v] ?? Weather.unknown;

  String get label {
    switch (this) {
      case Weather.sunny:
        return '晴';
      case Weather.cloudy:
        return '多云';
      case Weather.rainy:
        return '雨';
      case Weather.snowy:
        return '雪';
      case Weather.foggy:
        return '雾';
      case Weather.windy:
        return '风';
      case Weather.unknown:
        return '未知';
    }
  }

  String get emoji {
    switch (this) {
      case Weather.sunny:
        return '☀️';
      case Weather.cloudy:
        return '⛅';
      case Weather.rainy:
        return '🌧️';
      case Weather.snowy:
        return '❄️';
      case Weather.foggy:
        return '🌫️';
      case Weather.windy:
        return '🌬️';
      case Weather.unknown:
        return '🤷';
    }
  }

  // ---- 自定义 iconfont 图标（font-family: iconfont） ---------------------
  // 矢量、随主题色、任意大小。Weather.emoji 保留作为文本场景（如无图标字体
  // 时的兜底），UI 默认走 iconData / iconChar。
  static const _iconfontFamily = 'iconfont';

  /// 用于 [Icon] widget：呈现自定义天气图标（透明矢量，色随主题）。
  /// 注意：codepoint 必须是编译期常量（字面量），否则 release 构建的
  /// tree-shake-icons 无法静态分析而报错。
  IconData get iconData => switch (this) {
        Weather.sunny => const IconData(0xe90d, fontFamily: _iconfontFamily),
        Weather.cloudy => const IconData(0xe949, fontFamily: _iconfontFamily),
        Weather.rainy => const IconData(0xe912, fontFamily: _iconfontFamily),
        Weather.snowy => const IconData(0xe91a, fontFamily: _iconfontFamily),
        Weather.foggy => const IconData(0xe929, fontFamily: _iconfontFamily),
        Weather.windy => const IconData(0xe934, fontFamily: _iconfontFamily),
        Weather.unknown => const IconData(0xe948, fontFamily: _iconfontFamily),
      };

  /// 用于 [Text] / [TextSpan]（混排场景如 MetaLine）：在 `fontFamily: iconfont`
  /// 样式下渲染图标字符。
  String get iconChar => String.fromCharCode(_iconCode);

  int get _iconCode {
    switch (this) {
      case Weather.sunny:
        return 0xe90d; // qing
      case Weather.cloudy:
        return 0xe949; // duoyun
      case Weather.rainy:
        return 0xe912; // xiaoyu（小雨作通用雨）
      case Weather.snowy:
        return 0xe91a; // xiaoxue（小雪作通用雪）
      case Weather.foggy:
        return 0xe929; // wu
      case Weather.windy:
        return 0xe934; // weifeng（微风）
      case Weather.unknown:
        return 0xe948; // weizhi
    }
  }
}

enum ThemePreference { light, dark, system }

enum AccentKey { amber, rose, violet, emerald, sky, slate }

enum FontKey { sans, serif }

enum AssetKind { image, audio, video, attachment }

/// 附件引用（图片 / 音频 / 视频 / 文件）。
class AssetRef {
  final AssetKind kind;

  /// 相对 vault 根的路径，例如 "assets/images/<hash>.webp"。
  final String path;

  /// 原始文件名（用于展示 / 下载）。
  final String? name;
  final int? size;

  const AssetRef({
    required this.kind,
    required this.path,
    this.name,
    this.size,
  });

  factory AssetRef.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String?;
    final kind = AssetKind.values.asNameMap()[kindStr] ??
        AssetKind.attachment;
    return AssetRef(
      kind: kind,
      path: (json['path'] as String?) ?? '',
      name: json['name'] as String?,
      size: json['size'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'path': path,
        if (name != null) 'name': name,
        if (size != null) 'size': size,
      };

  AssetRef copyWith({String? path, String? name, int? size}) => AssetRef(
        kind: kind,
        path: path ?? this.path,
        name: name ?? this.name,
        size: size ?? this.size,
      );
}

/// 条目的元数据（frontmatter 中存储的部分）。
class JournalMeta {
  final String id;

  /// 条目所属日期，本地 YYYY-MM-DD。普通元数据：任意多条目可共享同一天。
  final String date;
  final String title;
  final Mood mood;
  final Weather weather;
  final String? location;
  final double? latitude; // 纬度（WGS-84；天地图瓦片为 CGCS2000，与 WGS-84 偏差 <1m，可直接共用）
  final double? longitude; // 经度
  final bool favorite; // 喜欢标记（frontmatter 里仅 true 时落盘）
  final List<String> tags;
  final List<AssetRef> assets;
  final String createdAt; // ISO 8601
  final String updatedAt; // ISO 8601

  const JournalMeta({
    required this.id,
    required this.date,
    required this.title,
    required this.mood,
    required this.weather,
    this.location,
    this.latitude,
    this.longitude,
    this.favorite = false,
    required this.tags,
    required this.assets,
    required this.createdAt,
    required this.updatedAt,
  });

  JournalMeta copyWith({
    String? id,
    String? date,
    String? title,
    Mood? mood,
    Weather? weather,
    String? location,
    bool clearLocation = false,
    double? latitude,
    double? longitude,
    bool? favorite,
    List<String>? tags,
    List<AssetRef>? assets,
    String? createdAt,
    String? updatedAt,
  }) =>
      JournalMeta(
        id: id ?? this.id,
        date: date ?? this.date,
        title: title ?? this.title,
        mood: mood ?? this.mood,
        weather: weather ?? this.weather,
        location: clearLocation ? null : (location ?? this.location),
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        favorite: favorite ?? this.favorite,
        tags: tags ?? this.tags,
        assets: assets ?? this.assets,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// 内存中的日记条目。`body` 为原始 Markdown 正文（不含 frontmatter）。
class JournalEntry extends JournalMeta {
  /// 原始 Markdown 正文（无 frontmatter）。
  final String body;

  /// 可选 TipTap JSON 文档（编辑器内部表示；移动端暂仅用 Markdown）。
  final Map<String, dynamic>? content;

  const JournalEntry({
    required super.id,
    required super.date,
    required super.title,
    required super.mood,
    required super.weather,
    super.location,
    super.latitude,
    super.longitude,
    super.favorite,
    required super.tags,
    required super.assets,
    required super.createdAt,
    required super.updatedAt,
    required this.body,
    this.content,
  });

  @override
  JournalEntry copyWith({
    String? id,
    String? date,
    String? title,
    Mood? mood,
    Weather? weather,
    String? location,
    bool clearLocation = false,
    double? latitude,
    double? longitude,
    bool? favorite,
    List<String>? tags,
    List<AssetRef>? assets,
    String? createdAt,
    String? updatedAt,
    String? body,
    Map<String, dynamic>? content,
  }) =>
      JournalEntry(
        id: id ?? this.id,
        date: date ?? this.date,
        title: title ?? this.title,
        mood: mood ?? this.mood,
        weather: weather ?? this.weather,
        location: clearLocation ? null : (location ?? this.location),
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        favorite: favorite ?? this.favorite,
        tags: tags ?? this.tags,
        assets: assets ?? this.assets,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        body: body ?? this.body,
        content: content ?? this.content,
      );

  /// 未命名时显示为「未命名」，与桌面端一致。
  String get displayTitle => title.isNotEmpty ? title : '未命名';
}
