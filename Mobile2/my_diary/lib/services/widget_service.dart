import 'package:home_widget/home_widget.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';

/// 桌面小组件展示数据（今日速览 + 最近一条）。
typedef WidgetData = ({
  String dateLabel,
  int todayCount,
  String todayMood,
  String latestTitle,
  String latestPreview,
});

/// 桌面小组件数据更新服务。
///
/// 从已加载的条目元数据计算「今日速览 + 最近一条」，写入 home_widget
/// 共享存储（Android 为 SharedPreferences("home_widget")），并通知
/// DiaryWidgetProvider 刷新。所有操作 fire-and-forget，不阻塞 UI。
class WidgetService {
  static const String androidProviderName = 'DiaryWidgetProvider';
  static const String _quickNewScheme = 'mydiary';
  static const String _quickNewHost = 'quick_new';

  /// 小组件「写日记」按钮的 URI（mydiary://quick_new）。
  static Uri quickNewUri() => Uri(scheme: _quickNewScheme, host: _quickNewHost);

  /// 是否为「写日记」入口 URI。
  static bool isQuickNew(Uri? uri) =>
      uri != null && uri.scheme == _quickNewScheme && uri.host == _quickNewHost;

  /// 冷启动检测：app 由小组件按钮拉起时返回入口 URI，否则 null。
  static Future<Uri?> initiallyLaunched() async {
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  /// 热启动事件流：app 已在后台时，小组件按钮点击经此推送。
  static Stream<Uri?> get widgetClicked => HomeWidget.widgetClicked;

  /// 计算小组件展示数据（纯函数，便于测试）。
  ///
  /// [entries] 需按「最新在前」排列（如 AppStore.entries）。
  static WidgetData compute(DateTime now, List<JournalEntry> entries) {
    final todayKey = _dateKey(now);
    final today = entries.where((e) => e.date == todayKey).toList();
    final latest = entries.isEmpty ? null : entries.first;
    return (
      dateLabel: _dateLabel(now),
      todayCount: today.length,
      todayMood: _dominantMood(today)?.label ?? '',
      latestTitle: latest?.title ?? '',
      latestPreview: latest == null ? '' : _preview(latest.body),
    );
  }

  /// 用当前条目数据刷新小组件（数据变化时调用）。
  static Future<void> updateEntries(
    List<JournalEntry> entries, {
    DateTime? now,
  }) async {
    try {
      final d = compute(now ?? DateTime.now(), entries);
      await HomeWidget.saveWidgetData<String>('dateLabel', d.dateLabel);
      await HomeWidget.saveWidgetData<int>('todayCount', d.todayCount);
      await HomeWidget.saveWidgetData<String>('todayMood', d.todayMood);
      await HomeWidget.saveWidgetData<String>('latestTitle', d.latestTitle);
      await HomeWidget.saveWidgetData<String>(
          'latestPreview', d.latestPreview);
      await HomeWidget.updateWidget(androidName: androidProviderName);
    } catch (_) {
      // 小组件更新失败不影响主流程。
    }
  }

  static String _dateKey(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static const List<String> _week = ['一', '二', '三', '四', '五', '六', '日'];
  static String _dateLabel(DateTime d) =>
      '${d.month}月${d.day}日 · 周${_week[d.weekday - 1]}';

  /// 今日出现次数最多的心情；无则 null。
  static Mood? _dominantMood(List<JournalEntry> today) {
    final counts = <Mood, int>{};
    for (final e in today) {
      counts[e.mood] = (counts[e.mood] ?? 0) + 1;
    }
    Mood? best;
    var bestCount = 0;
    counts.forEach((m, c) {
      if (c > bestCount) {
        best = m;
        bestCount = c;
      }
    });
    return best;
  }

  /// 摘要：剥掉 Markdown 标记、压缩空白、限长。
  static String _preview(String body) {
    final stripped = body.replaceAll(RegExp(r'[#>*`_~\[\]!()]'), '');
    final compact = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > 60 ? '${compact.substring(0, 60)}…' : compact;
  }
}
