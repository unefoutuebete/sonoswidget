package com.mba13.sonosarc

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

class SonosDiscovery(private val client: SonosSoapClient = SonosSoapClient(timeoutMs = 1200)) {
    suspend fun discover(): List<SonosSpeaker> = coroutineScope {
        val ssdp = async { runCatching { ssdpSpeakers() }.getOrDefault(emptyList()) }
        val scanned = async { runCatching { scanSubnet() }.getOrDefault(emptyList()) }
        val byUdn = LinkedHashMap<String, SonosSpeaker>()
        (ssdp.await() + scanned.await()).forEach { byUdn[it.udn] = it }
        byUdn.values.sortedWith(
            compareByDescending<SonosSpeaker> { it.looksLikeSoundbar }
                .thenBy { it.displayTitle.lowercase() },
        )
    }

    suspend fun speakerAt(ip: String) = client.fetchSpeaker(sanitizedIP(ip))

    private suspend fun ssdpSpeakers(): List<SonosSpeaker> {
        val hosts = withContext(Dispatchers.IO) { ssdpHosts() }
        return hosts.mapNotNull { host -> runCatching { client.fetchSpeaker(host) }.getOrNull() }
    }

    private suspend fun scanSubnet(): List<SonosSpeaker> = coroutineScope {
        val gate = Semaphore(40)
        candidateIPs().map { ip ->
            async(Dispatchers.IO) {
                gate.withPermit {
                    runCatching { client.fetchSpeaker(ip) }.getOrNull()
                }
            }
        }.awaitAll().filterNotNull()
    }

    private fun sanitizedIP(raw: String) = raw.trim()
        .removePrefix("http://")
        .substringBefore("/")
        .substringBefore(":")

    companion object {
        fun candidateIPs(): List<String> = ipv4Prefixes().flatMap { prefix ->
            (1..254).map { "$prefix.$it" }
        }

        fun ipv4Prefixes(): List<String> {
            val prefixes = mutableSetOf<String>()
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().forEach { iface ->
                if (!iface.isUp || iface.isLoopback) return@forEach
                iface.inetAddresses.toList().forEach { address ->
                    val host = address.hostAddress ?: return@forEach
                    if (host.contains(":") || host.startsWith("169.254")) return@forEach
                    val parts = host.split(".")
                    if (parts.size == 4) prefixes += parts.take(3).joinToString(".")
                }
            }
            return prefixes.toList()
        }

        private fun ssdpHosts(): Set<String> {
            val message = """
                M-SEARCH * HTTP/1.1
                HOST: 239.255.255.250:1900
                MAN: "ssdp:discover"
                MX: 1
                ST: urn:schemas-upnp-org:device:ZonePlayer:1

            """.trimIndent().replace("\n", "\r\n") + "\r\n"
            val socket = DatagramSocket()
            return try {
                socket.soTimeout = 2000
                val group = InetAddress.getByName("239.255.255.250")
                val bytes = message.toByteArray(Charsets.UTF_8)
                socket.send(DatagramPacket(bytes, bytes.size, group, 1900))
                val hosts = mutableSetOf<String>()
                val buffer = ByteArray(2048)
                val deadline = System.currentTimeMillis() + 2000
                while (System.currentTimeMillis() < deadline) {
                    try {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket.receive(packet)
                        val response = String(packet.data, 0, packet.length, Charsets.UTF_8)
                        val location = SonosXml.header("LOCATION", response) ?: continue
                        val host = locationHost(location) ?: continue
                        hosts += host
                    } catch (_: Exception) {
                        break
                    }
                }
                hosts
            } catch (_: Exception) {
                emptySet()
            } finally {
                socket.close()
            }
        }

        private fun locationHost(location: String): String? {
            val withoutScheme = location.removePrefix("http://").removePrefix("https://")
            return withoutScheme.substringBefore("/").substringBefore(":").ifBlank { null }
        }
    }
}
