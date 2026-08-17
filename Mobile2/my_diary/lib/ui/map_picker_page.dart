import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_diary_mobile/config/map_config.dart';
import 'package:my_diary_mobile/services/map_service.dart';

/// 地图选点页：在合规天地图瓦片上点击落点，自动逆地理编码填充地点名称，
/// 也可一键 GPS 定位。确定后回传 {lat, lon, name} 给调用方（编辑器）。
/// 天地图 Key 由 [MapConfig] 源码内配置（不在设置页）。
class MapPickerPage extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;

  const MapPickerPage({
    super.key,
    this.initialLat,
    this.initialLon,
  });

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  final MapController _mapController = MapController();
  late LatLng _center;
  double _zoom = 10;
  LatLng? _picked;
  bool _mapReady = false;
  bool _locating = false;
  bool _geocoding = false;
  final TextEditingController _nameCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLon != null) {
      _center = LatLng(widget.initialLat!, widget.initialLon!);
      _picked = _center;
      _zoom = 14;
    } else {
      _center = const LatLng(39.909187, 116.397451); // 北京兜底
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _onTap(LatLng point) async {
    setState(() {
      _picked = point;
      _geocoding = true;
    });
    final addr = await reverseGeocode(point.latitude, point.longitude);
    if (!mounted) return;
    setState(() {
      _geocoding = false;
      if (addr != null && addr.isNotEmpty) {
        _nameCtl.text = addr;
        _nameCtl.selection =
            TextSelection.fromPosition(TextPosition(offset: addr.length));
      }
    });
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
          .showSnackBar(const SnackBar(content: Text('无法获取定位，请检查定位权限')));
      return;
    }
    final p = LatLng(pos.latitude, pos.longitude);
    _mapController.move(p, 15);
    await _onTap(p);
  }

  void _confirm() {
    if (_picked == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, {
      'lat': _picked!.latitude,
      'lon': _picked!.longitude,
      'name': _nameCtl.text.trim(),
    });
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final z = (_mapController.camera.zoom + delta).clamp(0.0, 20.0);
    _mapController.move(_mapController.camera.center, z);
  }

  @override
  Widget build(BuildContext context) {
    final tiles = tdtTileLayers();
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择位置'),
        actions: [
          TextButton(onPressed: _confirm, child: const Text('确定')),
        ],
      ),
      body: Stack(
        children: [
          if (!MapConfig.isConfigured)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '未配置天地图密钥，无法加载地图\n'
                  '请在 lib/config/map_config.dart 中填写 Key',
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
                initialZoom: _zoom,
                onMapReady: () => setState(() => _mapReady = true),
                onTap: (_, point) => _onTap(point),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                ...tiles,
                if (_picked != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _picked!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_pin,
                            color: Colors.redAccent, size: 36),
                      ),
                    ],
                  ),
              ],
            ),
          // 版权标识
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
          // 缩放 / 定位控件
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
          // 选中点信息条
          if (_picked != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_geocoding)
                      const Text('正在解析地址…', style: TextStyle(fontSize: 12)),
                    TextField(
                      controller: _nameCtl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '地点名称（可修改）',
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${_picked!.latitude.toStringAsFixed(5)}, '
                      '${_picked!.longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
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
