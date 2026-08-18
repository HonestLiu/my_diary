import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

/// Frontmatter 的 YAML 编解码。
///
/// 写入：手写「块式（block）」YAML，键顺序与桌面端 `buildFrontmatter` 一致，
/// 字符串一律双引号（合法 YAML，桌面端 js-yaml 解析为字符串）。
/// 读取：用 `yaml` 包解析桌面端 js-yaml 的输出（块式 / 行内 `[]` 均可），
/// 再按 `normalizeMeta` 规则做类型归一化，保证双向互通。

const List<String> _fmKeys = [
  'id',
  'date',
  'title',
  'mood',
  'weather',
  'location',
  'latitude',
  'longitude',
  'favorite',
  'tags',
  'assets',
  'created_at',
  'updated_at',
];

String _yamlString(String s) {
  final escaped = s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
  return '"$escaped"';
}

String _yamlScalar(dynamic v) {
  if (v == null) return '""';
  if (v is num) return v.toString();
  if (v is bool) return v ? 'true' : 'false';
  return _yamlString(v.toString());
}

/// 生成 frontmatter 的 YAML 文本（不含 `---` 分隔符）。
String encodeFrontmatter(JournalEntry entry) {
  final buf = StringBuffer();
  buf.writeln('id: ${_yamlScalar(entry.id)}');
  buf.writeln('date: ${_yamlScalar(entry.date)}');
  buf.writeln('title: ${_yamlScalar(entry.title)}');
  buf.writeln('mood: ${_yamlScalar(entry.mood.name)}');
  buf.writeln('weather: ${_yamlScalar(entry.weather.name)}');
  buf.writeln('location: ${_yamlScalar(entry.location ?? '')}');
  if (entry.latitude != null) {
    buf.writeln('latitude: ${_yamlScalar(entry.latitude)}');
  }
  if (entry.longitude != null) {
    buf.writeln('longitude: ${_yamlScalar(entry.longitude)}');
  }
  // 喜欢标记：仅 true 时落盘（缺省即 false，保持旧文件最小改动）。
  if (entry.favorite) {
    buf.writeln('favorite: true');
  }

  if (entry.tags.isEmpty) {
    buf.writeln('tags: []');
  } else {
    buf.writeln('tags:');
    for (final t in entry.tags) {
      buf.writeln('  - ${_yamlScalar(t)}');
    }
  }

  if (entry.assets.isEmpty) {
    buf.writeln('assets: []');
  } else {
    buf.writeln('assets:');
    for (final a in entry.assets) {
      buf.writeln('  - kind: ${_yamlScalar(a.kind.name)}');
      buf.writeln('    path: ${_yamlScalar(a.path)}');
      if (a.name != null) buf.writeln('    name: ${_yamlScalar(a.name!)}');
      if (a.size != null) buf.writeln('    size: ${a.size}');
    }
  }

  buf.writeln('created_at: ${_yamlScalar(entry.createdAt)}');
  buf.writeln('updated_at: ${_yamlScalar(entry.updatedAt)}');
  return buf.toString().trimRight();
}

dynamic _deepToMap(dynamic node) {
  if (node is YamlMap) {
    return {for (final k in node.keys) k.toString(): _deepToMap(node[k])};
  }
  if (node is YamlList) {
    return node.map(_deepToMap).toList();
  }
  return node;
}

String _normalizeDateKey(dynamic v) {
  if (v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return v;
  return _formatKeyFallback();
}

String _formatKeyFallback() {
  final d = DateTime.now();
  final y = d.year;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _normalizeIso(dynamic v, String fallback) {
  if (v is String && v.isNotEmpty) return v;
  return fallback;
}

bool _isAssetRef(dynamic v) {
  if (v is! Map) return false;
  final kind = v['kind'];
  return v['path'] is String &&
      (kind == 'image' ||
          kind == 'audio' ||
          kind == 'video' ||
          kind == 'attachment');
}

/// 解析 frontmatter YAML 文本为归一化后的元数据。
JournalMeta parseFrontmatter(String text, {String? fallbackId}) {
  final nowIso = DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic> obj;
  try {
    final loaded = loadYaml(text);
    obj = (loaded == null ? <String, dynamic>{} : _deepToMap(loaded))
        as Map<String, dynamic>;
  } catch (_) {
    obj = <String, dynamic>{};
  }

  final id = (obj['id'] is String && (obj['id'] as String).isNotEmpty)
      ? obj['id'] as String
      : (fallbackId ?? const Uuid().v4());
  final date = _normalizeDateKey(obj['date']);
  final title = obj['title'] is String ? obj['title'] as String : '未命名';
  final mood = Mood.parse(obj['mood'] is String ? obj['mood'] as String : null);
  final weather =
      Weather.parse(obj['weather'] is String ? obj['weather'] as String : null);
  final location = obj['location'] is String ? obj['location'] as String : null;
  final latitude =
      obj['latitude'] is num ? (obj['latitude'] as num).toDouble() : null;
  final longitude =
      obj['longitude'] is num ? (obj['longitude'] as num).toDouble() : null;
  final favorite = obj['favorite'] == true;
  final tags = obj['tags'] is List
      ? (obj['tags'] as List)
          .whereType<String>()
          .toList()
      : <String>[];
  final assets = obj['assets'] is List
      ? (obj['assets'] as List)
          .where(_isAssetRef)
          .map((e) => AssetRef.fromJson(e as Map<String, dynamic>))
          .toList()
      : <AssetRef>[];
  final createdAt = _normalizeIso(obj['created_at'], nowIso);
  final updatedAt = _normalizeIso(obj['updated_at'], nowIso);

  return JournalMeta(
    id: id,
    date: date,
    title: title,
    mood: mood,
    weather: weather,
    location: location,
    latitude: latitude,
    longitude: longitude,
    favorite: favorite,
    tags: tags,
    assets: assets,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// 暴露给诊断/测试：把任意 Map 序列化为 YAML（仅用于断言，不进入落盘路径）。
String encodeMap(Map<String, dynamic> map) {
  final buf = StringBuffer();
  for (final k in _fmKeys) {
    if (!map.containsKey(k)) continue;
    final v = map[k];
    if (v is List) {
      if (v.isEmpty) {
        buf.writeln('$k: []');
      } else {
        buf.writeln('$k:');
        for (final item in v) {
          buf.writeln('  - ${_yamlScalar(item)}');
        }
      }
    } else {
      buf.writeln('$k: ${_yamlScalar(v)}');
    }
  }
  return buf.toString().trimRight();
}
