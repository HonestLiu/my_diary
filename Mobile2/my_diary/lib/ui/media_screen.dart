import 'dart:math';
import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/editor/doc_view.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:my_diary_mobile/ui/entry_card.dart';
import 'package:my_diary_mobile/ui/media_player.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

/// 媒体页的展示模式。
enum MediaMode {
  /// 扑克扇：按日记日期降序，两列铺满，每篇含媒体的日记是一个扑克扇单元。
  fan,
  /// 时间轴：左侧日期列 + 时间线圆点竖线，右侧卡片（标题 + 媒体缩略图）。
  timeline,
}

/// 媒体画廊，两种展示模式可切换：
/// - **扑克扇**：按日记所属日期（entry.date）降序，两列铺满；每篇含媒体的
///   日记是一个「扑克扇」单元（封面 + 两张纯色牌背做堆叠暗示），扇内浮动
///   该日记自己的日期；点扇展开该日记全部图片预览。
/// - **时间轴**：同样按日期降序，左侧日期（月-日 + 年份）+ 主题色圆点时间线，
///   右侧卡片（标题 + 媒体缩略图行），点击进预览。
class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  MediaMode _mode = MediaMode.fan;

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
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: Text('$total', style: context.caption)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<MediaMode>(
              segments: const [
                ButtonSegment(
                  value: MediaMode.fan,
                  icon: Icon(Icons.style_outlined),
                  tooltip: '扑克扇',
                ),
                ButtonSegment(
                  value: MediaMode.timeline,
                  icon: Icon(Icons.view_agenda_outlined),
                  tooltip: '时间轴',
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ],
      ),
      body: entries.isEmpty
          ? _EmptyMedia()
          : _mode == MediaMode.fan
              ? _buildFan(context, entries)
              : _buildTimeline(context, entries),
    );
  }

  /// 扑克扇布局：两列铺满，牌背右探 22 已计入 deck 尺寸。
  Widget _buildFan(BuildContext context, List<JournalEntry> entries) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 36),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final deckW = (constraints.maxWidth - 20) / 2;
          final coverW = deckW - 22;
          return Wrap(
            spacing: 20,
            runSpacing: 32,
            children: [
              for (final e in entries)
                _EntryFan(
                  entry: e,
                  coverW: coverW,
                  onOpen: () => _openPreview(context, e),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 时间轴布局：日期列 + 圆点竖线 + 内容卡片，按日期降序。
  Widget _buildTimeline(BuildContext context, List<JournalEntry> entries) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 36),
      itemCount: entries.length,
      itemBuilder: (_, i) => _TimelineItem(
        entry: entries[i],
        isLast: i == entries.length - 1,
        onOpen: () => _openPreview(context, entries[i]),
      ),
    );
  }
}

/// 一篇日记的媒体单元：多篇媒体时展开扑克扇（封面 + 两张纯色牌背做堆叠暗示），
/// 单媒体时只显示普通卡片；左上浮动该日记自己的日期。点击展开预览。
/// 封面尺寸按可用宽度等比缩放（基准 118 x 150），保证两列铺满。
class _EntryFan extends StatelessWidget {
  static const double _baseCardW = 118;
  static const double _baseCardH = 150;

  final JournalEntry entry;
  final double coverW;
  final VoidCallback onOpen;
  const _EntryFan({
    required this.entry,
    required this.coverW,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 只有多篇媒体才展开扑克扇；单媒体只显示普通卡片。
    final hasFan = entry.assets.length > 1;
    // 单卡与扑克扇共用同一外框尺寸，封面都锚定在左下角，
    // 从而保证单图卡与扑克扇的置顶图片位置完全平行。
    final cardW = coverW;
    final cardH = coverW * (_baseCardH / _baseCardW);
    final deckW = cardW + 22;
    final deckH = cardH + 16;
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
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(t.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: cardW,
          height: cardH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radiusCard),
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
              width: cardW,
              height: cardH,
              decoration: BoxDecoration(
                color: t.surfaceVariant,
                borderRadius: BorderRadius.circular(t.radiusCard),
                border: Border.all(color: t.border, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
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
                      // 音视频：软件内播放（页内直接可播），不再跳三方应用。
                      if (a.kind == AssetKind.video) {
                        return Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            child: InAppVideoPlayer(file: file),
                          ),
                        );
                      }
                      if (a.kind == AssetKind.audio) {
                        return Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InAppAudioPlayer(
                                    file: file, title: a.name ?? ''),
                              ],
                            ),
                          ),
                        );
                      }
                      // 附件：占位 + 交系统打开。
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
    // 渲染后的预览：解码正文为文档块，再压平成带行内样式的 span（保留加粗/斜体等）。
    final previewSpans = docBlocksToPreviewSpans(
      context,
      decodeEntryBody(entry.body, entry.assets),
      baseStyle: context.caption,
    );
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
                    Text.rich(
                      TextSpan(
                        children: previewSpans.isEmpty
                            ? [const TextSpan(text: '（暂无内容）')]
                            : previewSpans,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.caption,
                    ),
                    const SizedBox(height: 8),
                    MetaLine(entry: entry),
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

/// 非图片资产（视频 / 音频 / 附件）的占位视图。
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

/// 时间轴单个条目：左日期列 + 中时间线（圆点 + 贯穿竖线）+ 右内容卡片。
/// 卡片显示标题与媒体缩略图行（最多 4 张 + 计数），点击进入预览。
class _TimelineItem extends StatelessWidget {
  final JournalEntry entry;
  final bool isLast;
  final VoidCallback onOpen;
  const _TimelineItem({
    required this.entry,
    required this.isLast,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = context.cs;
    final d = _entryDate(entry);
    final store = context.read<AppStore>();
    final media = entry.assets;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 日期列：月-日 + 年份，右对齐。
          SizedBox(
            width: 74,
            child: Padding(
              padding: const EdgeInsets.only(top: 3, right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${d.month.toString().padLeft(2, '0')}-'
                    '${d.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text('${d.year}', style: context.caption),
                ],
              ),
            ),
          ),
          // 时间线：圆点 + 贯穿竖线（最后一条不延伸）。
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                    border: Border.all(color: cs.surface, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 3),
                      color: t.border,
                    ),
                  ),
              ],
            ),
          ),
          // 内容卡片。
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 8 : 20),
              child: Material(
                color: context.cs.surface,
                borderRadius: BorderRadius.circular(t.radiusCard),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpen,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.radiusCard),
                      border: Border.all(color: t.border, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: t.surfaceVariant,
                              borderRadius:
                                  BorderRadius.circular(t.radiusChip),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                child: Text('${media.length}',
                                    style: context.caption),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 缩略图行：横向滚动，图片再多也不溢出；最多平铺 6 张，
                        // 超出收进末尾「+N」徽章（点击卡片可看全部）。
                        SizedBox(
                          height: 64,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final a in media.take(6))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: _Thumb(
                                      asset: a,
                                      store: store,
                                      size: const Size(80, 64),
                                    ),
                                  ),
                                if (media.length > 6)
                                  Container(
                                    width: 44,
                                    height: 64,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: t.fill,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: t.border, width: 0.5),
                                    ),
                                    child: Text('+${media.length - 6}',
                                        style: context.caption.copyWith(
                                            fontWeight: FontWeight.w700)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间轴 / 卡片内的媒体缩略图（图片按 cover 裁切，非图片显示占位）。
class _Thumb extends StatelessWidget {
  final AssetRef asset;
  final AppStore store;
  final Size size;
  const _Thumb({required this.asset, required this.store, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final file = store.resolveAsset(asset.path);
    final inner = asset.kind == AssetKind.image
        ? Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                  color: t.fill,
                  child: const Icon(Icons.broken_image_outlined, size: 20),
                ),
          )
        : _kindPlaceholder(context, asset.kind, asset.name);
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
        color: t.fill,
      ),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );
  }
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
