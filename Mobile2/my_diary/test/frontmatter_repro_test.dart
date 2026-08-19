import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/vault/markdown_codec.dart';

/// 回归测试：桌面端（js-yaml frontmatter + tiptap-markdown 正文）创建的日记
/// 在移动端必须能正确解析 —— 图片/音频/视频被识别为 media，且不出现孤立的
/// `</attachment>` 文本或未解析的行内图片语法。
void main() {
  // 内容取自桌面端实际落盘文件（entries/2026/08/2026-08-19-*.md）。
  const desktopEntry = '''---
id: 25309af3-2cb7-42f1-aacf-467a123c24a4
date: '2026-08-19'
title: 测试
mood: neutral
weather: unknown
location: ''
tags: []
assets:
  - kind: image
    path: assets/images/72ebb9be0f18d82e.png
    name: image.png
    size: 1286792
  - kind: audio
    path: assets/audio/329fea4094ecf554.mp3
    name: sample-speech-5m.mp3
    size: 4801559
  - kind: video
    path: assets/video/05bd857af7f70bf5.mp4
    name: sample-5s.mp4
    size: 2848208
created_at: '2026-08-19T06:22:34.527Z'
updated_at: '2026-08-19T06:48:00.275Z'
---

# 测试

测试

![image.png](assets/images/72ebb9be0f18d82e.png)测试

<attachment src="assets/audio/329fea4094ecf554.mp3" name="sample-speech-5m.mp3" kind="audio" size="4801559" data-src="assets/audio/329fea4094ecf554.mp3" data-name="sample-speech-5m.mp3" data-kind="audio" data-size="4801559">
</attachment>

CDC的

<attachment src="assets/video/05bd857af7f70bf5.mp4" name="sample-5s.mp4" kind="video" size="2848208" data-src="assets/video/05bd857af7f70bf5.mp4" data-name="sample-5s.mp4" data-kind="video" data-size="2848208">
</attachment>

cscs
''';

  test('desktop-created entry: body decodes without stray tags/raw markdown',
      () {
    final parsed = parseEntryFile(desktopEntry);
    expect(parsed.meta.date, '2026-08-19');
    final blocks = decodeEntryBody(parsed.body, parsed.meta.assets);
    for (final b in blocks) {
      expect(b.text.contains('</attachment>'), isFalse,
          reason: '出现孤立 </attachment> 文本');
      expect(b.text.contains('!['), isFalse, reason: '出现未解析的行内图片语法');
    }
    // 图片（行内）、音频、视频都应被识别为 media。
    final mediaSrcs = blocks
        .where((b) => b.kind == BlockKind.media && b.media != null)
        .map((b) => b.media!.src)
        .toList();
    expect(
        mediaSrcs,
        contains('assets/images/72ebb9be0f18d82e.png'),
        reason: '行内图片未被识别');
    expect(mediaSrcs, contains('assets/audio/329fea4094ecf554.mp3'));
    expect(mediaSrcs, contains('assets/video/05bd857af7f70bf5.mp4'));
  });

  test('SyncManifest.fromJson accepts desktop snake_case keys', () {
    final m = SyncManifest.fromJson(jsonDecode('''
{"version":1,"device_id":"desktop","files":[],"generated_at":1787139348065}
''') as Map<String, dynamic>);
    expect(m.deviceId, 'desktop');
    expect(m.generatedAt, 1787139348065);
  });
}
