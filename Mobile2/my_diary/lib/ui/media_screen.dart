import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:provider/provider.dart';

/// 媒体画廊：聚合所有日记里的图片附件，网格浏览 + 大图查看。
class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = <MediaItem>[];
    for (final e in store.entries) {
      for (final a in e.assets.where((x) => x.kind == AssetKind.image)) {
        items.add(MediaItem(asset: a, title: e.displayTitle));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体'),
        actions: [
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${items.length}',
                    style: context.caption),
              ),
            ),
        ],
      ),
      body: items.isEmpty
          ? _EmptyMedia()
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final file =
                    context.read<AppStore>().resolveAsset(items[i].asset.path);
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          _MediaViewer(items: items, index: i),
                    ),
                  ),
                  child: Hero(
                    tag: items[i].asset.path,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(file,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class MediaItem {
  final AssetRef asset;
  final String title;
  const MediaItem({required this.asset, required this.title});
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
            Text('还没有图片', style: context.titleMedium),
            const SizedBox(height: 6),
            Text('在日记里添加照片，会在这里汇总。',
                style: context.caption),
          ],
        ),
      ),
    );
  }
}

class _MediaViewer extends StatefulWidget {
  final List<MediaItem> items;
  final int index;
  const _MediaViewer({required this.items, required this.index});

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.items[widget.index].title,
            style: const TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        itemBuilder: (_, i) {
          final file = context
              .read<AppStore>()
              .resolveAsset(widget.items[i].asset.path);
          return InteractiveViewer(
            child: Center(
              child: Hero(
                tag: widget.items[i].asset.path,
                child: Image.file(file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined,
                            color: Colors.white)),
              ),
            ),
          );
        },
      ),
    );
  }
}
