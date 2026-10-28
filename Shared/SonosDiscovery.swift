import Darwin
import Foundation

public struct SonosDiscovery: Sendable {
    private let client: SonosSOAPClient

    public init(client: SonosSOAPClient = SonosSOAPClient(timeout: 1.2)) {
        self.client = client
    }

    public func discover() async -> [SonosSpeaker] {
        async let ssdp = ssdpLocations()
        async let scanned = scanSubnet()
        var byUDN: [String: SonosSpeaker] = [:]
        for speaker in await ssdp + scanned {
            byUDN[speaker.udn] = speaker
        }
        return byUDN.values.sorted {
            if $0.looksLikeSoundbar != $1.looksLikeSoundbar {
                return $0.looksLikeSoundbar && !$1.looksLikeSoundbar
            }
            return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    public func speaker(at ip: String) async throws -> SonosSpeaker {
        try await client.fetchSpeaker(ip: sanitizedIP(ip))
    }

    public func resolve(udn: String, fallbackIP: String) async -> SonosSpeaker? {
        if let current = try? await client.fetchSpeaker(ip: fallbackIP), current.udn == udn {
            return current
        }
        return await discover().first(where: { $0.udn == udn })
    }

    private func ssdpLocations() async -> [SonosSpeaker] {
        let urls = await SSDP.search()
        var speakers: [SonosSpeaker] = []
        for url in urls {
            guard let host = url.host else { continue }
            if let speaker = try? await client.fetchSpeaker(ip: host) {
                speakers.append(speaker)
            }
        }
        return speakers
    }

    private func scanSubnet() async -> [SonosSpeaker] {
        let ips = Self.candidateIPs()
        return await withTaskGroup(of: SonosSpeaker?.self, returning: [SonosSpeaker].self) { group in
            var iterator = ips.makeIterator()
            var inFlight = 0
            var found: [SonosSpeaker] = []
            func enqueue() {
                while inFlight < 40, let ip = iterator.next() {
                    inFlight += 1
                    group.addTask { [client] in
                        try? await client.fetchSpeaker(ip: ip)
                    }
                }
            }
            enqueue()
            for await speaker in group {
                inFlight -= 1
                if let speaker {
                    found.append(speaker)
                }
                enqueue()
            }
            return found
        }
    }

    private func sanitizedIP(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "")
            .components(separatedBy: ":")
            .first ?? raw
    }

    static func candidateIPs() -> [String] {
        ipv4Prefixes().flatMap { prefix in
            (1...254).map { "\(prefix).\($0)" }
        }
    }

    static func ipv4Prefixes() -> [String] {
        var prefixes: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard ptr.pointee.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                ptr.pointee.ifa_addr,
                socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let ip = String(cString: hostname)
            if ip.hasPrefix("169.254") { continue }
            let parts = ip.split(separator: ".")
            guard parts.count == 4 else { continue }
            prefixes.append(parts.prefix(3).joined(separator: "."))
        }
        return Array(Set(prefixes))
    }
}

enum SSDP {
    static func search(timeoutSeconds: Int = 2) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            searchSync(timeoutSeconds: timeoutSeconds)
        }.value
    }

    private static func searchSync(timeoutSeconds: Int) -> [URL] {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return [] }
        defer { close(sock) }

        var ttl: UInt8 = 2
        setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout.size(ofValue: ttl)))

        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(1900).bigEndian
        _ = "239.255.255.250".withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }

        let message = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 1\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        \r
        """
        _ = message.withCString { pointer in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                    sendto(sock, pointer, strlen(pointer), 0, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var locations = Set<URL>()
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var buffer = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            let bytes = recv(sock, &buffer, buffer.count - 1, 0)
            guard bytes > 0 else { continue }
            let response = String(bytes: buffer.prefix(Int(bytes)), encoding: .utf8) ?? ""
            if let location = SonosXML.header("LOCATION", in: response),
               let url = URL(string: location) {
                locations.insert(url)
            }
        }
        return Array(locations)
    }
}
