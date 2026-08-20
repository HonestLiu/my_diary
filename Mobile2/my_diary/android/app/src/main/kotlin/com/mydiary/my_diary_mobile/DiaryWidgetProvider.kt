package com.mydiary.my_diary_mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 桌面小组件：今日速览 + 最近一条日记 + 快速写日记。
///
/// 数据由 Flutter 侧通过 `HomeWidget.saveWidgetData` 写入，本 provider 通过
/// [HomeWidgetProvider.onUpdate] 拿到 SharedPreferences 并渲染 RemoteViews；
/// 「写日记」按钮用 `HomeWidgetLaunchIntent` 打开 App 并携带
/// `mydiary://quick_new`，Flutter 侧据此直达编辑器。
class DiaryWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.diary_widget_layout).apply {
                // 今日速览
                val dateLabel = widgetData.getString("dateLabel", null).orEmpty()
                val todayCount = widgetData.getInt("todayCount", 0)
                val todayMood = widgetData.getString("todayMood", null).orEmpty()
                setTextViewText(R.id.widget_date, dateLabel)
                setTextViewText(
                    R.id.widget_today,
                    if (todayCount > 0) {
                        "今日 $todayCount 篇" + if (todayMood.isNotEmpty()) " · $todayMood" else ""
                    } else {
                        "今天还没有日记"
                    },
                )

                // 最近一条
                val latestTitle = widgetData.getString("latestTitle", null).orEmpty()
                val latestPreview = widgetData.getString("latestPreview", null).orEmpty()
                setTextViewText(R.id.widget_latest_title, latestTitle.ifEmpty { "—" })
                setTextViewText(R.id.widget_latest_preview, latestPreview)

                // 快速写日记：打开 App 并带 mydiary://quick_new，Flutter 侧检测后直达编辑器
                val launchIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("mydiary://quick_new"),
                )
                setOnClickPendingIntent(R.id.widget_new_button, launchIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
