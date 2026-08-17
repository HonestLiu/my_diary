import 'package:flutter/material.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/calendar_screen.dart';
import 'package:my_diary_mobile/ui/editor_screen.dart';
import 'package:my_diary_mobile/ui/home_screen.dart';
import 'package:my_diary_mobile/ui/map_screen.dart';
import 'package:my_diary_mobile/ui/media_screen.dart';
import 'package:my_diary_mobile/ui/profile_screen.dart';
import 'package:provider/provider.dart';

/// 应用外壳：底部导航条 + IndexedStack，承载四个主标签页。
/// 导航条：首页 / 日历 / 媒体 / 我的。FAB「写日记」仅首页显示。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _homeKey = GlobalKey<HomeScreenState>();

  static const _tabs = [
    _TabInfo(icon: Icons.book_outlined, active: Icons.book, label: '首页'),
    _TabInfo(
        icon: Icons.calendar_today_outlined,
        active: Icons.calendar_today,
        label: '日历'),
    _TabInfo(
        icon: Icons.photo_library_outlined,
        active: Icons.photo_library,
        label: '媒体'),
  _TabInfo(
      icon: Icons.person_outline, active: Icons.person, label: '我的'),
  _TabInfo(icon: Icons.map_outlined, active: Icons.map, label: '地图'),
];

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(key: _homeKey),
          const CalendarScreen(),
          const MediaScreen(),
          const ProfileScreen(),
          const MapScreen(),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                final entry = store.repo.newEntry();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EditorScreen(entry: entry)),
                ).then((_) => _homeKey.currentState?.refresh());
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('写日记'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.active),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final IconData active;
  final String label;
  const _TabInfo(
      {required this.icon, required this.active, required this.label});
}
