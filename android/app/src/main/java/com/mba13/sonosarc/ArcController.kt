package com.mba13.sonosarc

class ArcController(
    private val store: SpeakerStore,
    private val client: SonosSoapClient = SonosSoapClient(),
    private val discovery: SonosDiscovery = SonosDiscovery(),
) {
    fun snapshot() = store.load()

    suspend fun select(speaker: SonosSpeaker): ArcSnapshot {
        val snapshot = client.loadSnapshot(speaker)
        store.save(snapshot)
        return snapshot
    }

    suspend fun poll(): ArcSnapshot {
        val current = store.load() ?: throw SonosException("No speaker selected.")
        val state = client.pollHomeTheater(current.speaker.ip, current.speechEQ)
        val next = current.copy(
            nightMode = state.first,
            speechEnhancement = state.second,
            speechEQ = state.third,
            lastError = null,
            updatedAt = System.currentTimeMillis(),
        )
        store.save(next)
        return next
    }

    suspend fun refresh(): ArcSnapshot {
        val current = store.load() ?: throw SonosException("No speaker selected.")
        val speaker = runCatching { discovery.speakerAt(current.speaker.ip) }.getOrDefault(current.speaker)
        val next = client.loadSnapshot(speaker)
        store.save(next)
        return next
    }

    suspend fun setNightMode(on: Boolean, ip: String? = null) {
        val snapshot = resolvedSnapshot(ip) ?: return
        try {
            client.setEQ(snapshot.speaker.ip, HomeTheaterEQ.NightMode, on)
            store.save(
                snapshot.copy(nightMode = on, lastError = null, updatedAt = System.currentTimeMillis()),
            )
        } catch (error: Exception) {
            store.save(snapshot.copy(lastError = error.message))
        }
    }

    suspend fun setSpeech(on: Boolean, ip: String? = null) {
        val snapshot = resolvedSnapshot(ip) ?: return
        try {
            val kind = client.setSpeech(snapshot.speaker.ip, on, snapshot.speechEQ)
            store.save(
                snapshot.copy(
                    speechEnhancement = on,
                    speechEQ = kind,
                    lastError = null,
                    updatedAt = System.currentTimeMillis(),
                ),
            )
        } catch (error: Exception) {
            store.save(snapshot.copy(lastError = error.message))
        }
    }

    private fun resolvedSnapshot(ip: String?): ArcSnapshot? {
        val stored = store.load()
        if (stored != null) {
            return if (!ip.isNullOrBlank()) {
                stored.copy(speaker = stored.speaker.copy(ip = ip))
            } else {
                stored
            }
        }
        if (ip.isNullOrBlank()) return null
        return ArcSnapshot(
            speaker = SonosSpeaker(ip, "uuid:$ip", ip, "Sonos", ""),
            nightMode = false,
            speechEnhancement = false,
            speechEQ = SpeechEQKind.DialogLevel,
        )
    }
}
