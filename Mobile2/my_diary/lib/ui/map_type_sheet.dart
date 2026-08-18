import 'package:flutter/material.dart';
import 'package:my_diary_mobile/services/map_service.dart';

/// 地图类型选择底部弹层（矢量 / 影像 / 地形）。
/// 用户选择后返回新类型；未选择（点击遮罩）返回 null。
Future<TdtMapType?> showMapTypeSheet(
    BuildContext context, TdtMapType current) {
  return showModalBottomSheet<TdtMapType>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('地图类型',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          for (final t in TdtMapType.values)
            ListTile(
              dense: true,
              leading: Icon(
                t == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 18,
              ),
              title: Text(t.label),
              onTap: () => Navigator.pop(context, t),
            ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
}
