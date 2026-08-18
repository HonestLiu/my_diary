import 'package:flutter/material.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/calendar_screen.dart';
import 'package:my_diary_mobile/ui/editor_screen.dart';
import 'package:my_diary_mobile/ui/home_screen.dart';
import 'package:my_diary_mobile/ui/map_screen.dart';
import 'package:my_diary_mobile/ui/media_screen.dart';
import 'package:my_diary_mobile/ui/profile_screen.dart';
import 'package:provider/provider.dart';

/// 应用外壳：底部导航条 + IndexedStack，承载五个主标签页。
/// 导航条：首页 / 日历 / 媒体 / 地图 / 我的。FAB「写日记」仅首页显示。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _homeKey = GlobalKey<HomeScreenState>();

  /// 首页主列表滚动控制器：驱动 FAB 在「写日记」与「回到顶部」间切换。
  final _homeScroll = ScrollController();
  static const double _fabScrollThreshold = 160; // 滚动超过此像素切换形态
  bool _homeScrolled = false;

  @override
  void initState() {
    super.initState();
    _homeScroll.addListener(_onHomeScroll);
  }

  @override
  void dispose() {
    _homeScroll.dispose();
    super.dispose();
  }

  void _onHomeScroll() {
    final offset = _homeScroll.hasClients ? _homeScroll.offset : 0.0;
    final scrolled = offset > _fabScrollThreshold;
    if (scrolled != _homeScrolled) {
      setState(() => _homeScrolled = scrolled);
    }
  }

  void _scrollHomeToTop() {
    if (_homeScroll.hasClients) {
      _homeScroll.animateTo(0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic);
    }
  }

  void _openEditor(AppStore store) {
    final entry = store.repo.newEntry();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(entry: entry)),
    ).then((_) => _homeKey.currentState?.refresh());
  }

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
    _TabInfo(icon: Icons.map_outlined, active: Icons.map, label: '地图'),
    _TabInfo(
        icon: Icons.person_outline, active: Icons.person, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(key: _homeKey, controller: _homeScroll),
          const CalendarScreen(),
          const MediaScreen(),
          const MapScreen(),
          const ProfileScreen(),
        ],
      ),
      floatingActionButton: _index == 0
          ? _HomeFab(
              scrolled: _homeScrolled,
              onWrite: () => _openEditor(store),
              onTop: _scrollHomeToTop,
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

/// 首页悬浮按钮：单个 StadiumBorder 容器，宽度在「胶囊（写日记）」与
/// 「正圆（回到顶部）」间平滑变形，内容淡入淡出——避免两个不同尺寸
/// FAB 交叉切换的生硬跳变。
class _HomeFab extends StatelessWidget {
  final bool scrolled;
  final VoidCallback onWrite;
  final VoidCallback onTop;
  const _HomeFab({
    required this.scrolled,
    required this.onWrite,
    required this.onTop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: scrolled ? onTop : onWrite,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          height: 56,
          width: scrolled ? 56 : 112,
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 写日记：图标 + 文字（收起时淡出）。
              AnimatedOpacity(
                opacity: scrolled ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 22, color: cs.onPrimary),
                    const SizedBox(width: 6),
                    Text('写日记',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onPrimary)),
                  ],
                ),
              ),
              // 回到顶部：箭头（展开时淡入）。
              AnimatedOpacity(
                opacity: scrolled ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: Icon(Icons.vertical_align_top,
                    size: 24, color: cs.onPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
