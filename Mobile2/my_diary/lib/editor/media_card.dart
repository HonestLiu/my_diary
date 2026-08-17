import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

IconData iconForKind(AssetKind kind) {
  switch (kind) {
    case AssetKind.image:
      return Icons.image_outlined;
    case AssetKind.audio:
      return Icons.graphic_eq;
    case AssetKind.video:
      return Icons.play_circle_outline;
    case AssetKind.attachment:
      return Icons.insert_drive_file_outlined;
  }
}

String labelForKind(AssetKind kind) {
  switch (kind) {
    case AssetKind.image:
      return '图片';
    case AssetKind.audio:
      return '音频';
    case AssetKind.video:
      return '视频';
    case AssetKind.attachment:
      return '附件';
  }
}

/// 正文里的媒体块：图片直接预览，音视频 / 附件渲染为卡片并交由系统播放器打开。
///
/// 编辑态与只读态共用同一组件，只在编辑态显示删除按钮 —— 保证「所见即所得」。
class MediaBlockCard extends StatelessWidget {
  final MediaPayload media;
  final VoidCallback? onRemove;

  const MediaBlockCard({super.key, required this.media, this.onRemove});

  Future<void> _open(BuildContext context) async {
    final file = context.read<AppStore>().resolveAsset(media.src);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文件不存在，可能尚未同步到本机')));
      }
      return;
    }
    if (media.kind == AssetKind.image) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (c) => GestureDetector(
          onTap: () => Navigator.pop(c),
          child: InteractiveViewer(
            child: Center(child: Image.file(file)),
          ),
        ),
      );
      return;
    }
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法打开：${result.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final store = context.read<AppStore>();
    final file = store.resolveAsset(media.src);

    Widget content;
    if (media.kind == AssetKind.image) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(t.radiusCard),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: 360,
            maxWidth: media.width?.toDouble() ?? double.infinity,
          ),
          child: Image.file(
            file,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _missing(context),
          ),
        ),
      );
    } else {
      final subtitle = [
        labelForKind(media.kind),
        if (formatBytes(media.size).isNotEmpty) formatBytes(media.size),
      ].join(' · ');
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.fill,
          borderRadius: BorderRadius.circular(t.radiusCard),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconForKind(media.kind),
                  size: 20, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.name.isEmpty ? media.src.split('/').last : media.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: t.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.play_arrow_rounded, color: t.textSecondary),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _open(context),
      child: Stack(
        children: [
          content,
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: _RemoveButton(onTap: onRemove!),
            ),
        ],
      ),
    );
  }

  Widget _missing(BuildContext context) => Container(
        height: 120,
        alignment: Alignment.center,
        color: context.tokens.fill,
        child: Text('图片缺失',
            style: TextStyle(color: context.tokens.textSecondary)),
      );
}

class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RemoveButton({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: Icon(Icons.close, size: 16, color: Colors.white),
          ),
        ),
      );
}

/// 供列表/画廊复用的缩略图解析。
File resolveAssetFile(BuildContext context, String relPath) =>
    context.read<AppStore>().resolveAsset(relPath);
