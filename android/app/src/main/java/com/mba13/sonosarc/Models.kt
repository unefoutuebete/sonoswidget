package com.mba13.sonosarc

import org.json.JSONObject

enum class HomeTheaterEQ(val soapName: String) {
    NightMode("NightMode"),
    DialogLevel("DialogLevel"),
    SpeechEnhanceEnabled("SpeechEnhanceEnabled"),
}

enum class SpeechEQKind {
    DialogLevel,
    SpeechEnhanceEnabled;

    val eq: HomeTheaterEQ
        get() = when (this) {
            DialogLevel -> HomeTheaterEQ.DialogLevel
            SpeechEnhanceEnabled -> HomeTheaterEQ.SpeechEnhanceEnabled
        }

    companion object {
        fun fromRaw(raw: String?) = entries.find { it.name.equals(raw, ignoreCase = true) }
            ?: DialogLevel
    }
}

data class SonosSpeaker(
    val ip: String,
    val udn: String,
    val roomName: String,
    val modelName: String,
    val modelNumber: String,
) {
    val displayTitle: String
        get() = roomName.ifBlank { modelName }

    val displaySubtitle: String
        get() {
            val model = modelName.ifBlank { modelNumber }
            return "$model · $ip"
        }

    val looksLikeSoundbar: Boolean
        get() {
            val number = modelNumber.uppercase()
            if (number in soundbarModelNumbers) return true
            return containsProductName("arc", modelName) || containsProductName("beam", modelName)
        }

    fun toJson() = JSONObject()
        .put("ip", ip)
        .put("udn", udn)
        .put("roomName", roomName)
        .put("modelName", modelName)
        .put("modelNumber", modelNumber)

    companion object {
        private val soundbarModelNumbers = setOf("S14", "S17", "S19", "S38", "S47")

        fun fromJson(obj: JSONObject) = SonosSpeaker(
            ip = obj.optString("ip"),
            udn = obj.optString("udn"),
            roomName = obj.optString("roomName"),
            modelName = obj.optString("modelName"),
            modelNumber = obj.optString("modelNumber"),
        )

        private fun containsProductName(name: String, modelName: String): Boolean {
            return Regex("\\b${Regex.escape(name)}\\b", RegexOption.IGNORE_CASE)
                .containsMatchIn(modelName)
        }
    }
}

data class ArcSnapshot(
    val speaker: SonosSpeaker,
    val nightMode: Boolean,
    val speechEnhancement: Boolean,
    val speechEQ: SpeechEQKind,
    val lastError: String? = null,
    val updatedAt: Long = System.currentTimeMillis(),
) {
    fun toJson() = JSONObject()
        .put("speaker", speaker.toJson())
        .put("nightMode", nightMode)
        .put("speechEnhancement", speechEnhancement)
        .put("speechEQ", speechEQ.name)
        .put("lastError", lastError)
        .put("updatedAt", updatedAt)

    companion object {
        fun fromJson(raw: String): ArcSnapshot {
            val obj = JSONObject(raw)
            return ArcSnapshot(
                speaker = SonosSpeaker.fromJson(obj.getJSONObject("speaker")),
                nightMode = obj.optBoolean("nightMode"),
                speechEnhancement = obj.optBoolean("speechEnhancement"),
                speechEQ = SpeechEQKind.fromRaw(obj.optString("speechEQ")),
                lastError = obj.optString("lastError").ifBlank { null },
                updatedAt = obj.optLong("updatedAt", System.currentTimeMillis()),
            )
        }
    }
}

class SonosException(message: String) : Exception(message)
