package com.mba13.sonosarc

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class ArcWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { updateAppWidget(context, appWidgetManager, it) }
        refreshFromSpeaker(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TOGGLE_NIGHT -> toggle(context, night = true)
            ACTION_TOGGLE_SPEECH -> toggle(context, night = false)
            ACTION_REFRESH -> refreshFromSpeaker(context)
        }
    }

    private fun toggle(context: Context, night: Boolean) {
        scope.launch {
            val store = SpeakerStore(context)
            val snapshot = store.load() ?: return@launch
            val controller = ArcController(store)
            if (night) {
                controller.setNightMode(!snapshot.nightMode)
            } else {
                controller.setSpeech(!snapshot.speechEnhancement)
            }
            updateAll(context)
        }
    }

    private fun refreshFromSpeaker(context: Context) {
        scope.launch {
            runCatching { ArcController(SpeakerStore(context)).poll() }
            updateAll(context)
        }
    }

    companion object {
        const val ACTION_TOGGLE_NIGHT = "com.mba13.sonosarc.TOGGLE_NIGHT"
        const val ACTION_TOGGLE_SPEECH = "com.mba13.sonosarc.TOGGLE_SPEECH"
        const val ACTION_REFRESH = "com.mba13.sonosarc.REFRESH_WIDGET"
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ArcWidgetProvider::class.java))
            ids.forEach { updateAppWidget(context, manager, it) }
        }

        private fun updateAppWidget(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
            val snapshot = SpeakerStore(context).load()
            val views = RemoteViews(context.packageName, R.layout.widget_arc)
            if (snapshot == null) {
                views.setTextViewText(R.id.widget_title, "Sonos Arc")
                views.setTextViewText(R.id.widget_status, "Open the app and choose your Arc.")
                views.setViewVisibility(R.id.night_button, View.GONE)
                views.setViewVisibility(R.id.speech_button, View.GONE)
            } else {
                views.setTextViewText(R.id.widget_title, snapshot.speaker.displayTitle)
                views.setTextViewText(
                    R.id.widget_status,
                    snapshot.lastError ?: snapshot.speaker.displaySubtitle,
                )
                views.setViewVisibility(R.id.night_button, View.VISIBLE)
                views.setViewVisibility(R.id.speech_button, View.VISIBLE)
                views.setTextViewText(R.id.night_button, if (snapshot.nightMode) "Night on" else "Night")
                views.setTextViewText(R.id.speech_button, if (snapshot.speechEnhancement) "Speech on" else "Speech")
            }
            views.setOnClickPendingIntent(
                R.id.night_button,
                pendingBroadcast(context, ACTION_TOGGLE_NIGHT, 1),
            )
            views.setOnClickPendingIntent(
                R.id.speech_button,
                pendingBroadcast(context, ACTION_TOGGLE_SPEECH, 2),
            )
            views.setOnClickPendingIntent(
                R.id.widget_root,
                pendingBroadcast(context, ACTION_REFRESH, 3),
            )
            manager.updateAppWidget(appWidgetId, views)
        }

        private fun pendingBroadcast(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, ArcWidgetProvider::class.java).setAction(action)
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
