import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/services/map_service.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:provider/provider.dart';

/// 足迹地图：把全部带经纬度的日记标注在天地图上，按缩放级别网格聚类；
/// 单击标点进入详情，聚簇点展开列表。合规源：天地图 WMTS。
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final LatLng _center = const LatLng(39.909187, 116.397451); // 北京兜底
  static const double _minZoom = 0;
  static const double _maxZoom = 20;
  double _currentZoom = 4;
  bool _mapReady = false;
  bool _locating = false;

  List<JournalEntry> _entries = [];
  List<Marker> _markers = [];
  VoidCallback? _storeListener;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    store.addListener(_onStoreChange);
    _syncEntries(store);
  }

  @override
  void dispose() {
    if (_storeListener != null) {
      try {
        context.read<AppStore>().removeListener(_storeListener!);
      } catch (_) {}
    }
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) _syncEntries(context.read<AppStore>());
  }

  void _syncEntries(AppStore store) {
    final list = store.entries
        .where((e) => e.latitude != null && e.longitude != null)
        .toList();
    final changed = list.length != _entries.length ||
        list.any((e) => !_entries.any((o) => o.id == e.id));
    if (changed) {
      _entries = list;
      if (_mapReady) _buildMarkers();
    }
  }

  void _buildMarkers() {
    if (_entries.isEmpty) {
      setState(() => _markers = const []);
      return;
    }
    final z = _currentZoom.clamp(_minZoom, _maxZoom);
    final pixelsPerWorld = 256.0 * math.pow(2.0, z);
    final degPerPixelLon = 360.0 / pixelsPerWorld;
    const gridPx = 80.0;
    final bucketDegLon = degPerPixelLon * gridPx;
    final bucketDegLat = bucketDegLon;

    String bucketKey(double lat, double lon) {
      final by = (lat / bucketDegLat).floor();
      final bx = (lon / bucketDegLon).floor();
      return '$by,$bx';
    }

    final Map<String, List<JournalEntry>> buckets = {};
    for (final e in _entries) {
      final key = bucketKey(e.latitude!, e.longitude!);
      (buckets[key] ??= <JournalEntry>[]).add(e);
    }

    final store = context.read<AppStore>();
    final List<Marker> markers = [];
    buckets.forEach((_, list) {
      if (list.isEmpty) return;
      double latSum = 0, lonSum = 0;
      for (final e in list) {
        latSum += e.latitude!;
        lonSum += e.longitude!;
      }
      final lat = latSum / list.length;
      final lon = lonSum / list.length;
      final rep = list.firstWhere(
        (e) => e.assets.any((a) => a.kind == AssetKind.image),
        orElse: () => list.first,
      );
      ImageProvider? provider;
      final img = rep.assets.where((a) => a.kind == AssetKind.image).firstOrNull;
      if (img != null) {
        final file = store.resolveAsset(img.path);
        if (file.existsSync()) provider = FileImage(file);
      }
      markers.add(Marker(
        point: LatLng(lat, lon),
        width: 76,
        height: 82,
        alignment: Alignment.topCenter,
        child: _GroupMarker(
          hasImage: provider != null,
          provider: provider,
          count: list.length,
          onTap: () {
            if (list.length == 1) {
              _openDetail(list.first);
            } else {
              _openGroup(list);
            }
          },
        ),
      ));
    });
    setState(() => _markers = markers);
  }

  void _openDetail(JournalEntry e) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(entry: e)),
    );
  }

  void _openGroup(List<JournalEntry> group) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('该地点 ${group.length} 篇日记',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          for (final e in group)
            ListTile(
              leading: const Icon(Icons.book_outlined),
              title: Text(e.displayTitle),
              subtitle: Text(e.date),
              onTap: () {
                Navigator.pop(context);
                _openDetail(e);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final pos = await getCurrentPosition();
    if (!mounted) {
      setState(() => _locating = false);
      return;
    }
    setState(() => _locating = false);
    if (pos == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法获取定位')));
      return;
    }
    _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final z = (_mapController.camera.zoom + delta).clamp(_minZoom, _maxZoom);
    _mapController.move(_mapController.camera.center, z);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final key = store.settings.mapKey;
    final tiles = tdtTileLayers(key);
    return Scaffold(
      appBar: AppBar(
        title: const Text('足迹'),
        actions: [
          if (_entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text('${_entries.length} 个地点',
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (key.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '未配置天地图密钥，无法加载地图\n请到「设置 → 地图（天地图）」填写 Key',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
              ),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _currentZoom,
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                onMapReady: () {
                  setState(() {
                    _mapReady = true;
                    _currentZoom = _mapController.camera.zoom;
                  });
                  _buildMarkers();
                },
                onMapEvent: (event) {
                  if (!_mapReady) return;
                  final newZoom = _mapController.camera.zoom;
                  final needRecluster =
                      (newZoom - _currentZoom).abs() >= 0.25;
                  setState(() => _currentZoom = newZoom);
                  if (needRecluster) _buildMarkers();
                },
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                ...tiles,
                MarkerLayer(markers: _markers),
              ],
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(tdtCopyright,
                  style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
          if (key.isNotEmpty)
            Positioned(
              right: 8,
              top: 8,
              child: Column(
                children: [
                  _RoundBtn(icon: Icons.add, onTap: _mapReady ? () => _zoomBy(1) : null),
                  const SizedBox(height: 6),
                  _RoundBtn(icon: Icons.remove, onTap: _mapReady ? () => _zoomBy(-1) : null),
                  const SizedBox(height: 6),
                  _RoundBtn(
                    icon: Icons.my_location,
                    onTap: _locating ? null : _locate,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 聚簇/单点标记：有图显示缩略圆，无图显示图标圆，多篇文章显示红色计数角标。
class _GroupMarker extends StatelessWidget {
  final bool hasImage;
  final ImageProvider? provider;
  final int count;
  final VoidCallback onTap;
  const _GroupMarker({
    required this.hasImage,
    required this.provider,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                padding: hasImage ? null : const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasImage ? null : Colors.deepPurple,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                  ],
                  image: hasImage
                      ? DecorationImage(image: provider!, fit: BoxFit.cover)
                      : null,
                ),
                child: hasImage
                    ? null
                    : const Icon(Icons.description, size: 28, color: Colors.white),
              ),
              if (count > 1)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆形浮动按钮（缩放 / 定位）。
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundBtn({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled ? Colors.grey.shade400 : Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon,
              size: 20,
              color: disabled ? Colors.grey.shade600 : Colors.black87),
        ),
      ),
    );
  }
}
