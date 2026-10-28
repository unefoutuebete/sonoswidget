package com.mba13.sonosarc

import android.content.Context

class SpeakerStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): ArcSnapshot? {
        val raw = prefs.getString(KEY, null) ?: return null
        return runCatching { ArcSnapshot.fromJson(raw) }.getOrNull()
    }

    fun save(snapshot: ArcSnapshot) {
        prefs.edit().putString(KEY, snapshot.toJson().toString()).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS = "sonos_arc"
        private const val KEY = "snapshot"
    }
}
