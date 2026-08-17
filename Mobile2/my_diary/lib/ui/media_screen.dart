import 'dart:math';
import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

/// 媒体画廊：按日记所属日期（entry.date）降序，按行优先横向铺满、排不下自动换行；
/// 每篇含媒体的日记是一个「扑克扇」单元（封面 + 两张纯色牌背做堆叠暗示），
/// 扇内浮动该日记自己的日期（entry.date）；点扇展开该日记全部图片预览，
/// 预览窗下方一条白色信息条（类似首页卡片），点条跳转对应日记。
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
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 36),
              child: Wrap(
                spacing: 20,
                runSpacing: 32,
                children: [
                  for (final e in entries)
                    _EntryFan(
                      entry: e,
                      onOpen: () => _openPreview(context, e),
                    ),
                ],
              ),
            ),
    );
  }
}

/// 一篇日记的媒体单元：多篇媒体时展开扑克扇（封面 + 两张纯色牌背做堆叠暗示），
/// 单媒体时只显示普通卡片；左上浮动该日记自己的日期。点击展开预览。
class _EntryFan extends StatelessWidget {
  static const double _cardW = 118;
  static const double _cardH = 150;

  final JournalEntry entry;
  final VoidCallback onOpen;
  const _EntryFan({required this.entry, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 只有多篇媒体才展开扑克扇；单媒体只显示普通卡片。
    final hasFan = entry.assets.length > 1;
    // 单卡与扑克扇共用同一外框尺寸，封面都锚定在左下角，
    // 从而保证单图卡与扑克扇的置顶图片位置完全平行。
    final deckW = _cardW + 22;
    final deckH = _cardH + 16;
    final cover = entry.assets.first;
    final file = context.read<AppStore>().resolveAsset(cover.path);
    final isImage = cover.kind == AssetKind.image;

    final coverInner = isImage
        ? Image.file(file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                  color: t.fill,
                  child: const Icon(Icons.broken_image_outlined),
                ))
        : _kindPlaceholder(context, cover.kind, cover.name);

    final coverCard = Hero(
      tag: 'media-${entry.id}',
      child: Material(
        elevation: 8,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(t.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: _cardW,
          height: _cardH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radiusCard),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: coverInner,
        ),
      ),
    );

    // 牌背：仅多篇媒体时做堆叠暗示，不显示图片。
    Widget echo(double dx, double dy, double deg) => Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: deg * pi / 180,
            child: Container(
              width: _cardW,
              height: _cardH,
              decoration: BoxDecoration(
                color: t.surfaceVariant,
                borderRadius: BorderRadius.circular(t.radiusCard),
                border: Border.all(color: t.border, width: 1),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        );

    final deckChildren = <Widget>[];
    if (hasFan) {
      deckChildren.add(echo(16, -14, 7));
      deckChildren.add(echo(8, -7, 3.5));
    }
    deckChildren.add(Positioned(left: 0, bottom: 0, child: coverCard));

    final deck = SizedBox(
      width: deckW,
      height: deckH,
      child: Stack(clipBehavior: Clip.none, children: deckChildren),
    );

    // 日期胶囊：浮动于卡片上缘；有扇时略高于卡片，单卡时贴边上缘。
    final datePill = Positioned(
      left: 6,
      top: hasFan ? -4 : 6,
      child: Material(
        elevation: 6,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(t.radiusChip),
        color: context.cs.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Text(
            _formatDate(_entryDate(entry)),
            style: context.caption.copyWith(
                fontWeight: FontWeight.w700, color: t.textPrimary),
          ),
        ),
      ),
    );

    final children = <Widget>[deck, datePill];
    // 多于 1 个媒体时，右下角小计数徽章提示「还有更多」。
    if (hasFan) {
      children.add(Positioned(
        right: 0,
        bottom: -2,
        child: Material(
          elevation: 4,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(t.radiusChip),
          color: context.cs.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Text('${entry.assets.length}',
                style: context.caption.copyWith(
                    fontWeight: FontWeight.w700, color: t.textPrimary)),
          ),
        ),
      ));
    }

    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: deckW,
        height: deckH + 8,
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }
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
