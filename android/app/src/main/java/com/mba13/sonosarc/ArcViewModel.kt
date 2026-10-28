package com.mba13.sonosarc

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class ArcUiState(
    val snapshot: ArcSnapshot? = null,
    val speakers: List<SonosSpeaker> = emptyList(),
    val isDiscovering: Boolean = false,
    val isWorking: Boolean = false,
    val message: String? = null,
    val pollError: String? = null,
    val manualIp: String = "",
)

class ArcViewModel(application: Application) : AndroidViewModel(application) {
    private val store = SpeakerStore(application)
    private val controller = ArcController(store)
    private val discovery = SonosDiscovery()
    private val _state = MutableStateFlow(ArcUiState(snapshot = store.load()))
    val state = _state.asStateFlow()
    private var pollJob: Job? = null

    fun setManualIp(value: String) {
        _state.value = _state.value.copy(manualIp = value)
    }

    fun startPolling() {
        if (pollJob != null) return
        pollJob = viewModelScope.launch {
            poll()
            while (isActive) {
                delay(5_000)
                poll()
            }
        }
    }

    fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    fun discover() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isDiscovering = true, message = "Looking for Sonos on Wi-Fi…")
            val found = discovery.discover()
            _state.value = _state.value.copy(
                isDiscovering = false,
                speakers = found,
                message = if (found.isEmpty()) {
                    "No speakers found. Stay on the same Wi-Fi as Sonos, then try an IP."
                } else {
                    "Found ${found.size} speaker${if (found.size == 1) "" else "s"}."
                },
            )
        }
    }

    fun connect(speaker: SonosSpeaker) {
        viewModelScope.launch {
            runWork {
                val next = controller.select(speaker)
                _state.value = _state.value.copy(
                    snapshot = next,
                    message = widgetHint(next, "Using ${next.speaker.displayTitle}."),
                )
                ArcWidgetProvider.updateAll(getApplication())
            }
        }
    }

    fun connectManual() {
        val ip = _state.value.manualIp.trim()
        if (ip.isEmpty()) return
        viewModelScope.launch {
            runWork {
                val speaker = discovery.speakerAt(ip)
                val next = controller.select(speaker)
                val speakers = _state.value.speakers
                _state.value = _state.value.copy(
                    snapshot = next,
                    speakers = if (speakers.any { it.udn == speaker.udn }) speakers else listOf(speaker) + speakers,
                    message = widgetHint(next, "Using ${next.speaker.displayTitle}."),
                )
                ArcWidgetProvider.updateAll(getApplication())
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            runWork {
                val next = controller.refresh()
                _state.value = _state.value.copy(snapshot = next, pollError = null)
                ArcWidgetProvider.updateAll(getApplication())
            }
        }
    }

    fun setNight(on: Boolean) {
        viewModelScope.launch {
            val current = _state.value.snapshot ?: return@launch
            _state.value = _state.value.copy(snapshot = current.copy(nightMode = on))
            controller.setNightMode(on)
            _state.value = _state.value.copy(snapshot = store.load())
            ArcWidgetProvider.updateAll(getApplication())
        }
    }

    fun setSpeech(on: Boolean) {
        viewModelScope.launch {
            val current = _state.value.snapshot ?: return@launch
            _state.value = _state.value.copy(snapshot = current.copy(speechEnhancement = on))
            controller.setSpeech(on)
            _state.value = _state.value.copy(snapshot = store.load())
            ArcWidgetProvider.updateAll(getApplication())
        }
    }

    fun forget() {
        store.clear()
        _state.value = _state.value.copy(
            snapshot = null,
            pollError = null,
            message = "Choose a speaker to control from the widget.",
        )
        ArcWidgetProvider.updateAll(getApplication())
    }

    private suspend fun poll() {
        if (_state.value.snapshot == null) return
        try {
            val next = controller.poll()
            _state.value = _state.value.copy(snapshot = next, pollError = null)
        } catch (error: Exception) {
            _state.value = _state.value.copy(pollError = error.message)
        }
    }

    private suspend fun runWork(block: suspend () -> Unit) {
        _state.value = _state.value.copy(isWorking = true)
        try {
            block()
        } catch (error: Exception) {
            _state.value = _state.value.copy(
                message = error.message,
                snapshot = store.load(),
            )
        } finally {
            _state.value = _state.value.copy(isWorking = false)
        }
    }

    private fun widgetHint(snapshot: ArcSnapshot, prefix: String): String {
        val extra = if (!snapshot.speaker.looksLikeSoundbar) {
            " This model may not support Night Mode or Speech Enhancement."
        } else {
            ""
        }
        return "$prefix$extra Long-press the Home Screen, add the Sonos Arc widget, then tap Night or Speech."
    }
}
