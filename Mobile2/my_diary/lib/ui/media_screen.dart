import 'dart:math';
import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

/// 媒体画廊：按日记所属日期（entry.date）降序，用紧凑网格横向铺满、自动换行；
/// 每篇含媒体的日记是一张封面瓦片，呈现扑克扇效果（封面在前、最多两张副卡在右后方微旋露出），
/// 日期直接叠在封面图左上，多媒体的篇在右上标数量；
/// 点瓦片展开该日记全部图片预览，预览窗下方一条白色信息条（类似首页卡片），点条跳转对应日记。
class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    // 含媒体的日记，按日记所属日期（entry.date）降序排列。
    final entries = store.entries
        .where((e) => e.assets.isNotEmpty)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final total = entries.fold(0, (s, e) => s + e.assets.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体'),
        actions: [
          if (total > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('$total', style: context.caption)),
            ),
        ],
      ),
      body: entries.isEmpty
          ? _EmptyMedia()
          : LayoutBuilder(
              builder: (ctx, constraints) {
                final cols = _columns(constraints.maxWidth);
                const gap = 8.0;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: 1,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (c, i) => _EntryTile(
                    entry: entries[i],
                    onOpen: () => _openPreview(c, entries[i]),
                  ),
                );
              },
            ),
    );
  }
}

/// 根据可用宽度决定每行列数：窄屏 2 列，宽屏最多 5 列。
int _columns(double w) {
  if (w >= 720) return 5;
  if (w >= 540) return 4;
  if (w >= 380) return 3;
  return 2;
}

/// 一篇日记的封面瓦片：扑克扇（封面在前、最多两张副卡在右后方微旋露出），
/// 日期叠在封面左上，多媒体的篇在右上标数量。点瓦片展开该日记全部图片预览。
class _EntryTile extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onOpen;
  const _EntryTile({required this.entry, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final assets = entry.assets;
    final cover = assets.first;
    // 副卡：封面之后的前两张，作为扑克扇的后半部分。
    final backs = assets.skip(1).take(2).toList();

    // 扑克扇：副卡在封面右后方微旋露出，营造"一摞卡片"的层次。
    const backAngles = [7.0, -8.0];
    const backOffX = [11.0, -9.0];
    const backOffY = [9.0, -7.0];

    Widget buildBack(AssetRef a, double angle, double offX, double offY) {
      return Positioned.fill(
        child: Transform.translate(
          offset: Offset(offX, offY),
          child: Transform.rotate(
            angle: angle * pi / 180,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.radiusCard),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(t.radiusCard),
                child: _tileThumb(context, a, dim: 0.3),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onOpen,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 副卡（先画在底层）。
          for (int i = 0; i < backs.length; i++)
            buildBack(backs[i], backAngles[i], backOffX[i], backOffY[i]),
          // 封面（最上层），承载日期 / 角标与 hero 过渡。
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.radiusCard),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Hero(
                tag: 'media-${entry.id}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _tileThumb(context, cover),
                    // 顶部渐隐遮罩，保证日期 / 角标在浅色图上也清晰可读。
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 7,
                      top: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(t.radiusChip),
                        ),
                        child: Text(
                          _formatDate(_entryDate(entry)),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    if (entry.assets.length > 1)
                      Positioned(
                        right: 7,
                        top: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(t.radiusChip),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.collections_outlined,
                                  size: 12, color: Colors.white),
                              const SizedBox(width: 2),
                              Text('${entry.assets.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单张卡片缩略图：图片直接铺满，非图片用占位；dim 不为空则叠一层暗化遮罩增强层次。
Widget _tileThumb(BuildContext context, AssetRef a, {double? dim}) {
  final t = context.tokens;
  final file = context.read<AppStore>().resolveAsset(a.path);
  final isImage = a.kind == AssetKind.image;
  final child = isImage
      ? Image.file(file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
                color: t.fill,
                child: Icon(Icons.broken_image_outlined, color: t.textTertiary),
              ))
      : _kindPlaceholder(context, a.kind, a.name);
  if (dim != null) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Container(color: Colors.black.withValues(alpha: dim)),
      ],
    );
  }
  return child;
}

/// 弹出预览：上部图片查看器（该日记全部媒体），下部透明毛玻璃条（类似首页卡片）。
void _openPreview(BuildContext context, JournalEntry entry) {
  final root = Navigator.of(context, rootNavigator: true);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _PreviewSheet(
      entry: entry,
      onOpenDiary: () {
        root.pop();
        root.push(
          MaterialPageRoute(builder: (_) => DetailScreen(entry: entry)),
        );
      },
    ),
  );
}

class _PreviewSheet extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onOpenDiary;
  const _PreviewSheet({required this.entry, required this.onOpenDiary});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = entry.assets;
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(t.radiusSheet)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _PreviewHeader(entry: entry),
          Expanded(
            child: media.isEmpty
                ? const Center(
                    child: Text('该日记暂无媒体',
                        style: TextStyle(color: Colors.white70)))
                : PageView.builder(
                    itemCount: media.length,
                    itemBuilder: (_, i) {
                      final a = media[i];
                      final file =
                          context.read<AppStore>().resolveAsset(a.path);
                      if (a.kind == AssetKind.image) {
                        final img = Image.file(
                          file,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white),
                        );
                        return InteractiveViewer(
                          child: Center(
                            child: i == 0
                                ? Hero(tag: 'media-${entry.id}', child: img)
                                : img,
                          ),
                        );
                      }
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _kindPlaceholder(context, a.kind, a.name),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: () => OpenFilex.open(file.path),
                              icon: const Icon(Icons.open_in_new_outlined),
                              label: const Text('用其他应用打开'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          _PreviewBar(entry: entry, onOpenDiary: onOpenDiary),
        ],
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  final JournalEntry entry;
  const _PreviewHeader({required this.entry});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12))),
      child: Row(
        children: [
          Expanded(
            child: Text(entry.displayTitle,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// 预览窗下方白色信息条：内容类似首页日记卡片（标题 + 预览 + 心情/天气/定位/标签），
/// 点击跳转对应日记。
class _PreviewBar extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onOpenDiary;
  const _PreviewBar({required this.entry, required this.onOpenDiary});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final preview = entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final loc = entry.location ?? '';
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onOpenDiary,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.displayTitle,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      preview.isEmpty ? '（暂无内容）' : preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.caption,
                    ),
                    _metaRow(context, entry, loc),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: t.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 复刻首页卡片底部：心情 / 天气 / 定位 / 标签 同一行（空间不足自动换行）。
Widget _metaRow(BuildContext context, JournalEntry entry, String loc) {
  final t = context.tokens;
  final chips = <Widget>[
    _metaItem(context, '${entry.mood.emoji} ${entry.mood.label}'),
    _metaItem(context, '${entry.weather.emoji} ${entry.weather.label}'),
    if (loc.isNotEmpty) _metaItem(context, loc, icon: Icons.place_outlined),
    ...entry.tags.map((tag) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: BorderRadius.circular(t.radiusChip),
          ),
          child: Text('#$tag',
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
        )),
  ];
  if (chips.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    ),
  );
}

Widget _metaItem(BuildContext context, String text, {IconData? icon}) {
  final tertiary = context.tokens.textTertiary;
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 13, color: tertiary),
        const SizedBox(width: 3),
      ],
      Text(text, style: TextStyle(fontSize: 12, color: tertiary)),
    ],
  );
}

Widget _kindPlaceholder(
    BuildContext context, AssetKind kind, String? name) {
  final t = context.tokens;
  final icon = kind == AssetKind.video
      ? Icons.play_circle_outline
      : kind == AssetKind.audio
          ? Icons.audiotrack
          : Icons.insert_drive_file;
  final tint = kind == AssetKind.video
      ? Colors.blueGrey
      : kind == AssetKind.audio
          ? Colors.deepPurple
          : Colors.teal;
  return Container(
    width: double.infinity,
    height: double.infinity,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [t.surfaceVariant, t.fill],
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 34, color: tint),
        if (name != null && name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.caption),
          ),
      ],
    ),
  );
}

class _EmptyMedia extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: t.surfaceVariant,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.photo_library_outlined,
                  size: 36, color: t.textTertiary),
            ),
            const SizedBox(height: 18),
            Text('还没有媒体', style: context.titleMedium),
            const SizedBox(height: 6),
            Text('在日记里添加照片、视频或音频，会按日记在这里汇总。',
                style: context.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

DateTime _entryDate(JournalEntry e) {
  // 以日记所属日期为准（用户可手动修改），仅当 date 非法时回退到创建时间。
  final d = DateTime.tryParse(e.date);
  if (d != null) return d;
  final p = DateTime.tryParse(e.createdAt);
  return p ?? DateTime.now();
}

String _formatDate(DateTime d) {
  const wk = ['日', '一', '二', '三', '四', '五', '六'];
  return '${d.year}年${d.month}月${d.day}日 周${wk[d.weekday % 7]}';
}
