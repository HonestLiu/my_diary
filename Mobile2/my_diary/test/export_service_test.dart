import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/services/export_service.dart';

void main() {
  group('ExportService.rewriteBodyForExport', () {
    test('图片引用加相对路径前缀', () {
      const md = '正文\n\n![](assets/images/a.png)\n\n![x](assets/images/b.webp)';
      expect(
        ExportService.rewriteBodyForExport(md, '../../../'),
        '正文\n\n![](../../../assets/images/a.png)\n\n'
        '![x](../../../assets/images/b.webp)',
      );
    });

    test('音频 <attachment> 转 HTML5 <audio>（含下载兜底）', () {
      const md =
          '<attachment data-src="assets/audio/录音.m4a" '
          'data-name="录音.m4a" data-kind="audio" data-size="20480">'
          '</attachment>';
      final out = ExportService.rewriteBodyForExport(md, '../../../');
      expect(
        out,
        '<audio src="../../../assets/audio/录音.m4a" controls '
        'preload="metadata">您的浏览器不支持音频播放，'
        '<a href="../../../assets/audio/录音.m4a" download="录音.m4a">'
        '点击下载</a></audio>',
      );
    });

    test('视频 <attachment> 转 HTML5 <video>（data-width 生效）', () {
      const md =
          '<attachment data-src="assets/video/c.mp4" data-name="clip.mp4" '
          'data-kind="video" data-size="1024" data-width="320"></attachment>';
      final out = ExportService.rewriteBodyForExport(md, '../../../');
      expect(out, contains('<video src="../../../assets/video/c.mp4"'));
      expect(out, contains('controls preload="metadata"'));
      expect(out, contains('style="max-width:100%;width:320px"'));
      expect(out, contains('点击下载</a></video>'));
    });

    test('视频 inline 模式属性不影响导出为 <video>', () {
      const md =
          '<attachment data-src="assets/video/c.mp4" data-name="clip.mp4" '
          'data-kind="video" data-size="1024" data-video-mode="inline">'
          '</attachment>';
      final out = ExportService.rewriteBodyForExport(md, '../../../');
      expect(out, contains('<video src="../../../assets/video/c.mp4"'));
      expect(out, contains('</video>'));
    });

    test('附件转下载链接', () {
      const md =
          '<attachment data-src="assets/attachments/doc.pdf" '
          'data-name="文档.pdf" data-kind="attachment" data-size="99">'
          '</attachment>';
      final out = ExportService.rewriteBodyForExport(md, '../');
      expect(
        out,
        '<a href="../assets/attachments/doc.pdf" download="文档.pdf">'
        '文档.pdf</a>',
      );
    });

    test('frontmatter 保持 vault 根相对原样，只改正文', () {
      const md = '''---
id: abc
date: 2026-08-18
assets:
  - path: assets/video/c.mp4
---

<attachment data-src="assets/video/c.mp4" data-name="c.mp4"
 data-kind="video" data-size="10"></attachment>
''';
      final out = ExportService.rewriteBodyForExport(md, '../../');
      expect(out, contains('path: assets/video/c.mp4')); // frontmatter 不动
      expect(out, contains('<video src="../../assets/video/c.mp4"'));
    });

    test('自闭合 <attachment …/> 同样转换', () {
      const md =
          '<attachment data-src="assets/audio/a.m4a" data-name="a.m4a" '
          'data-kind="audio" data-size="1"/>';
      final out = ExportService.rewriteBodyForExport(md, '../');
      expect(out, contains('<audio src="../assets/audio/a.m4a"'));
    });
  });
}
