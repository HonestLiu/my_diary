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

// ---------------------------------------------------------------------------
// 快速 frontmatter 解析（自产块式 YAML 快路径；识别不了回退 loadYaml）
// ---------------------------------------------------------------------------

final RegExp _fmKeyRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');

/// 反解 `_yamlString` 写入的双引号字符串转义。
String _unescapeDoubleQuoted(String s) {
  final sb = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '\\' && i + 1 < s.length) {
      final e = s[i + 1];
      switch (e) {
        case 'n':
          sb.write('\n');
          break;
        case 'r':
          sb.write('\r');
          break;
        case 't':
          sb.write('\t');
          break;
        case '"':
          sb.write('"');
          break;
        case '\\':
          sb.write('\\');
          break;
        default:
          sb
            ..write('\\')
            ..write(e); // 未知转义原样保留（罕见，值仍为字符串）
      }
      i += 2;
    } else {
      sb.write(c);
      i++;
    }
  }
  return sb.toString();
}

/// 解析单个标量：双引号字符串 / 数字 / bool / null / 裸字符串。
/// 行内集合（`[...]`/`{...}`）或块标量（`|`/`>`）返回 [_unsupported] 让调用方回退。
Object _unsupported = Object();

dynamic _fastScalar(String s) {
  final v = s.trim();
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    return _unescapeDoubleQuoted(v.substring(1, v.length - 1));
  }
  if (v.isEmpty || v == '~' || v == 'null') return null;
  if (v.startsWith('[') || v.startsWith('{') || v.startsWith('|') || v.startsWith('>')) {
    return _unsupported;
  }
  if (v == 'true') return true;
  if (v == 'false') return false;
  final n = num.tryParse(v);
  if (n != null) return n;
  return v; // 裸字符串（桌面端可能不加引号）
}

/// 快速解析自产（或桌面端）frontmatter 的块式 YAML：
/// 顶层 `key: scalar` / `key:` 空值 / `key:` 块式列表（列表项可为
/// 标量或内嵌 map，如 tags / assets）。仅覆盖我们生成的固定格式；
/// 任何意外形态返回 null，由 [parseFrontmatter] 回退 `loadYaml`，
/// 保证与桌面端 js-yaml 的互通不受影响。
Map<String, dynamic>? _tryFastParse(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final map = <String, dynamic>{};
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      i++;
      continue;
    }
    if (line.startsWith(' ') || line.startsWith('\t')) return null; // 意外缩进
    final colon = line.indexOf(':');
    if (colon <= 0) return null;
    final key = line.substring(0, colon).trim();
    if (!_fmKeyRe.hasMatch(key)) return null;
    final value = line.substring(colon + 1).trim();
    i++;

    if (value.isEmpty) {
      if (i < lines.length && lines[i].startsWith('  - ')) {
        final list = <dynamic>[];
        while (i < lines.length && lines[i].startsWith('  - ')) {
          final itemRest = lines[i].substring(4).trim();
          i++;
          final itemMap = <String, dynamic>{};
          final firstColon = itemRest.indexOf(':');
          if (firstColon > 0) {
            // 内联首键："- kind: x"
            final k = itemRest.substring(0, firstColon).trim();
            final v = itemRest.substring(firstColon + 1).trim();
            if (!_fmKeyRe.hasMatch(k) || v.isEmpty) return null;
            final sv = _fastScalar(v);
            if (identical(sv, _unsupported)) return null;
            itemMap[k] = sv;
          } else if (itemRest.isNotEmpty) {
            final sv = _fastScalar(itemRest);
            if (identical(sv, _unsupported)) return null;
            list.add(sv);
            continue;
          }
          // map 项其余键（4 空格缩进）；比 assets 更深（>2 层）→ 回退
          while (i < lines.length &&
              lines[i].startsWith('    ') &&
              !lines[i].startsWith('    -')) {
            final sub = lines[i].substring(4);
            final c = sub.indexOf(':');
            if (c <= 0) return null;
            final k = sub.substring(0, c).trim();
            final v = sub.substring(c + 1).trim();
            if (!_fmKeyRe.hasMatch(k) || v.isEmpty) return null;
            final sv = _fastScalar(v);
            if (identical(sv, _unsupported)) return null;
            itemMap[k] = sv;
            i++;
          }
          list.add(itemMap);
        }
        map[key] = list;
      } else {
        map[key] = null; // 空标量
      }
    } else {
      final sv = _fastScalar(value);
      if (identical(sv, _unsupported)) return null;
      map[key] = sv;
    }
  }
  return map;
}

/// 解析 frontmatter YAML 文本为归一化后的元数据。
JournalMeta parseFrontmatter(String text, {String? fallbackId}) {
  final nowIso = DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic> obj;
  try {
    // 快路径：我们自产的块式格式毫秒级解析；失败/未知形态回退 yaml 包，
    // 保证与桌面端 js-yaml 输出完全兼容。
    final fast = _tryFastParse(text);
    if (fast != null) {
      obj = fast;
    } else {
      final loaded = loadYaml(text);
      obj = (loaded == null ? <String, dynamic>{} : _deepToMap(loaded))
          as Map<String, dynamic>;
    }
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
