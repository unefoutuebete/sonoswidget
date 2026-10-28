package com.mba13.sonosarc

object SonosXml {
    fun tag(name: String, xml: String): String? {
        val escaped = Regex.escape(name)
        val pattern = Regex(
            "<(?:[\\w-]+:)?$escaped(?:\\s[^>]*)?>([\\s\\S]*?)</(?:[\\w-]+:)?$escaped>",
            RegexOption.IGNORE_CASE,
        )
        val value = pattern.find(xml)?.groupValues?.getOrNull(1)?.trim().orEmpty()
        return value.ifEmpty { null }
    }

    fun currentValue(soap: String) = tag("CurrentValue", soap)

    fun isSoapFault(xml: String) =
        xml.contains("<s:Fault") || xml.contains("<SOAP-ENV:Fault") || xml.contains("UPnPError")

    fun boolValue(raw: String?): Boolean? {
        val value = raw?.trim()?.lowercase().orEmpty()
        if (value.isEmpty()) return null
        if (value in setOf("1", "true", "on", "yes")) return true
        if (value in setOf("0", "false", "off", "no")) return false
        return value.toIntOrNull()?.let { it != 0 }
    }

    fun header(name: String, response: String): String? {
        response.lineSequence().forEach { line ->
            val parts = line.split(":", limit = 2)
            if (parts.size == 2 && parts[0].trim().equals(name, ignoreCase = true)) {
                return parts[1].trim()
            }
        }
        return null
    }

    fun speaker(fromDeviceDescription: String, ip: String): SonosSpeaker {
        return SonosSpeaker(
            ip = ip,
            udn = tag("UDN", fromDeviceDescription) ?: "uuid:$ip",
            roomName = tag("roomName", fromDeviceDescription)
                ?: tag("displayName", fromDeviceDescription)
                ?: tag("friendlyName", fromDeviceDescription)
                ?: ip,
            modelName = tag("modelName", fromDeviceDescription)
                ?: tag("displayName", fromDeviceDescription)
                ?: "Sonos",
            modelNumber = tag("modelNumber", fromDeviceDescription).orEmpty(),
        )
    }

    fun soapEnvelope(action: String, body: String) = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:$action xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
        $body
            </u:$action>
          </s:Body>
        </s:Envelope>
    """.trimIndent()
}
