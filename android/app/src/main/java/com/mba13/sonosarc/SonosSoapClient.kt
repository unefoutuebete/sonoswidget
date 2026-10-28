package com.mba13.sonosarc

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class SonosSoapClient(private val timeoutMs: Int = 4000) {
    suspend fun fetchSpeaker(ip: String): SonosSpeaker = withContext(Dispatchers.IO) {
        val xml = httpGet("http://$ip:1400/xml/device_description.xml")
        SonosXml.speaker(xml, ip)
    }

    suspend fun getEQ(ip: String, type: HomeTheaterEQ): Boolean = getEQValue(ip, type) != 0

    suspend fun getEQValue(ip: String, type: HomeTheaterEQ): Int = withContext(Dispatchers.IO) {
        val xml = soap(
            ip,
            "GetEQ",
            """
              <InstanceID>0</InstanceID>
              <EQType>${type.soapName}</EQType>
            """.trimIndent(),
        )
        val raw = SonosXml.currentValue(xml) ?: throw SonosException("Unexpected response from the speaker.")
        raw.trim().toIntOrNull() ?: if (SonosXml.boolValue(raw) == true) 1 else 0
    }

    suspend fun setEQ(ip: String, type: HomeTheaterEQ, on: Boolean) = withContext(Dispatchers.IO) {
        soap(
            ip,
            "SetEQ",
            """
              <InstanceID>0</InstanceID>
              <EQType>${type.soapName}</EQType>
              <DesiredValue>${if (on) 1 else 0}</DesiredValue>
            """.trimIndent(),
        )
        Unit
    }

    suspend fun setSpeech(ip: String, on: Boolean, preferred: SpeechEQKind): SpeechEQKind {
        val order = if (preferred == SpeechEQKind.DialogLevel) {
            listOf(SpeechEQKind.DialogLevel, SpeechEQKind.SpeechEnhanceEnabled)
        } else {
            listOf(SpeechEQKind.SpeechEnhanceEnabled, SpeechEQKind.DialogLevel)
        }
        var last: Exception? = null
        for (kind in order) {
            try {
                setEQ(ip, kind.eq, on)
                return kind
            } catch (error: Exception) {
                last = error
            }
        }
        throw last ?: SonosException("This speaker does not support Night Mode or Speech Enhancement.")
    }

    suspend fun readHomeTheater(ip: String): Triple<Boolean, Boolean, SpeechEQKind> {
        val night = getEQ(ip, HomeTheaterEQ.NightMode)
        val description = runCatching { fetchControlDescription(ip) }.getOrDefault("")
        val dialog = runCatching { getEQValue(ip, HomeTheaterEQ.DialogLevel) }.getOrNull()
        val supportsSpeechEnhance =
            description.contains("SpeechEnhanceEnabled", ignoreCase = true) || (dialog ?: 0) > 1
        if (supportsSpeechEnhance) {
            runCatching { getEQ(ip, HomeTheaterEQ.SpeechEnhanceEnabled) }.getOrNull()?.let {
                return Triple(night, it, SpeechEQKind.SpeechEnhanceEnabled)
            }
        }
        if (dialog != null) {
            return Triple(night, dialog != 0, SpeechEQKind.DialogLevel)
        }
        val speech = runCatching { getEQ(ip, HomeTheaterEQ.SpeechEnhanceEnabled) }.getOrNull()
            ?: throw SonosException("This speaker does not support Night Mode or Speech Enhancement.")
        return Triple(night, speech, SpeechEQKind.SpeechEnhanceEnabled)
    }

    suspend fun pollHomeTheater(ip: String, speechEQ: SpeechEQKind): Triple<Boolean, Boolean, SpeechEQKind> {
        val night = getEQ(ip, HomeTheaterEQ.NightMode)
        runCatching { getEQ(ip, speechEQ.eq) }.getOrNull()?.let {
            return Triple(night, it, speechEQ)
        }
        val fallback = if (speechEQ == SpeechEQKind.DialogLevel) {
            SpeechEQKind.SpeechEnhanceEnabled
        } else {
            SpeechEQKind.DialogLevel
        }
        runCatching { getEQ(ip, fallback.eq) }.getOrNull()?.let {
            return Triple(night, it, fallback)
        }
        throw SonosException("This speaker does not support Night Mode or Speech Enhancement.")
    }

    suspend fun loadSnapshot(speaker: SonosSpeaker): ArcSnapshot {
        val (night, speech, kind) = readHomeTheater(speaker.ip)
        return ArcSnapshot(speaker, night, speech, kind)
    }

    private suspend fun fetchControlDescription(ip: String) = withContext(Dispatchers.IO) {
        httpGet("http://$ip:1400/xml/RenderingControl1.xml")
    }

    private fun soap(ip: String, action: String, body: String): String {
        val url = URL("http://$ip:1400/MediaRenderer/RenderingControl/Control")
        val envelope = SonosXml.soapEnvelope(action, body)
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            doOutput = true
            useCaches = false
            setRequestProperty("Content-Type", "text/xml; charset=\"utf-8\"")
            setRequestProperty(
                "SOAPACTION",
                "\"urn:schemas-upnp-org:service:RenderingControl:1#$action\"",
            )
        }
        return try {
            connection.outputStream.use { it.write(envelope.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val xml = stream?.bufferedReader(Charsets.UTF_8)?.readText().orEmpty()
            if (SonosXml.isSoapFault(xml)) {
                throw SonosException(
                    SonosXml.tag("errorDescription", xml)
                        ?: SonosXml.tag("errorCode", xml)
                        ?: SonosXml.tag("faultstring", xml)
                        ?: "SOAP fault",
                )
            }
            if (status !in 200..299) {
                throw SonosException("Speaker returned HTTP $status.")
            }
            xml
        } catch (error: SonosException) {
            throw error
        } catch (_: Exception) {
            throw SonosException("Could not reach the speaker on Wi-Fi.")
        } finally {
            connection.disconnect()
        }
    }

    private fun httpGet(url: String): String {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            useCaches = false
        }
        return try {
            val status = connection.responseCode
            if (status !in 200..299) throw SonosException("Speaker returned HTTP $status.")
            connection.inputStream.bufferedReader(Charsets.UTF_8).readText()
        } catch (error: SonosException) {
            throw error
        } catch (_: Exception) {
            throw SonosException("Could not reach the speaker on Wi-Fi.")
        } finally {
            connection.disconnect()
        }
    }
}
