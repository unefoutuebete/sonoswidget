import Foundation

public struct SonosSOAPClient: Sendable {
    private let session: URLSession

    public init(timeout: TimeInterval = 4) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    public func fetchSpeaker(ip: String) async throws -> SonosSpeaker {
        let url = try url(host: ip, path: "/xml/device_description.xml")
        let data = try await data(from: url)
        guard let xml = String(data: data, encoding: .utf8),
              let speaker = SonosXML.speaker(fromDeviceDescription: xml, ip: ip) else {
            throw SonosError.parse
        }
        return speaker
    }

    public func getEQ(ip: String, type: HomeTheaterEQ) async throws -> Bool {
        let value = try await getEQValue(ip: ip, type: type)
        return value != 0
    }

    public func getEQValue(ip: String, type: HomeTheaterEQ) async throws -> Int {
        let xml = try await soap(ip: ip, action: "GetEQ", body: """
              <InstanceID>0</InstanceID>
              <EQType>\(type.rawValue)</EQType>
        """)
        guard let raw = SonosXML.currentValue(in: xml) else {
            throw SonosError.parse
        }
        if let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return value
        }
        guard let flag = SonosXML.boolValue(from: raw) else {
            throw SonosError.parse
        }
        return flag ? 1 : 0
    }

    public func setEQ(ip: String, type: HomeTheaterEQ, on: Bool) async throws {
        _ = try await soap(ip: ip, action: "SetEQ", body: """
              <InstanceID>0</InstanceID>
              <EQType>\(type.rawValue)</EQType>
              <DesiredValue>\(on ? 1 : 0)</DesiredValue>
        """)
    }

    public func setSpeech(ip: String, on: Bool, preferred: SpeechEQKind) async throws -> SpeechEQKind {
        let order: [SpeechEQKind] = preferred == .dialogLevel
            ? [.dialogLevel, .speechEnhanceEnabled]
            : [.speechEnhanceEnabled, .dialogLevel]
        var lastError: Error = SonosError.unsupportedSpeaker
        for kind in order {
            do {
                try await setEQ(ip: ip, type: kind.eq, on: on)
                return kind
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    public func readHomeTheater(ip: String) async throws -> (night: Bool, speech: Bool, speechEQ: SpeechEQKind) {
        let night = try await getEQ(ip: ip, type: .nightMode)
        let description = (try? await fetchControlDescription(ip: ip)) ?? ""
        let dialog = try? await getEQValue(ip: ip, type: .dialogLevel)
        let supportsSpeechEnhance = description.localizedCaseInsensitiveContains("SpeechEnhanceEnabled")
            || (dialog ?? 0) > 1

        if supportsSpeechEnhance, let speech = try? await getEQ(ip: ip, type: .speechEnhanceEnabled) {
            return (night, speech, .speechEnhanceEnabled)
        }
        if let dialog {
            return (night, dialog != 0, .dialogLevel)
        }
        if let speech = try? await getEQ(ip: ip, type: .speechEnhanceEnabled) {
            return (night, speech, .speechEnhanceEnabled)
        }
        throw SonosError.unsupportedSpeaker
    }

    public func pollHomeTheater(ip: String, speechEQ: SpeechEQKind) async throws -> (night: Bool, speech: Bool, speechEQ: SpeechEQKind) {
        let night = try await getEQ(ip: ip, type: .nightMode)
        if let speech = try? await getEQ(ip: ip, type: speechEQ.eq) {
            return (night, speech, speechEQ)
        }
        let fallback: SpeechEQKind = speechEQ == .dialogLevel ? .speechEnhanceEnabled : .dialogLevel
        if let speech = try? await getEQ(ip: ip, type: fallback.eq) {
            return (night, speech, fallback)
        }
        throw SonosError.unsupportedSpeaker
    }

    public func loadSnapshot(for speaker: SonosSpeaker) async throws -> ArcSnapshot {
        let state = try await readHomeTheater(ip: speaker.ip)
        return ArcSnapshot(
            speaker: speaker,
            nightMode: state.night,
            speechEnhancement: state.speech,
            speechEQ: state.speechEQ
        )
    }

    public func fetchControlDescription(ip: String) async throws -> String {
        let url = try url(host: ip, path: "/xml/RenderingControl1.xml")
        let data = try await data(from: url)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw SonosError.parse
        }
        return xml
    }

    private func soap(ip: String, action: String, body: String) async throws -> String {
        let url = try url(host: ip, path: "/MediaRenderer/RenderingControl/Control")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "\"urn:schemas-upnp-org:service:RenderingControl:1#\(action)\"",
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = SonosXML.soapEnvelope(action: action, body: body).data(using: .utf8)
        let (data, status) = try await dataAndStatus(from: request)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw SonosError.parse
        }
        if SonosXML.isSOAPFault(xml) {
            throw SonosError.soapFault(
                SonosXML.tag("errorDescription", in: xml)
                    ?? SonosXML.tag("errorCode", in: xml)
                    ?? SonosXML.tag("faultstring", in: xml)
                    ?? "SOAP fault"
            )
        }
        if !(200...299).contains(status) {
            throw SonosError.httpStatus(status)
        }
        return xml
    }

    private func url(host: String, path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = 1400
        components.path = path
        guard let url = components.url else { throw SonosError.invalidURL }
        return url
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, status) = try await dataAndStatus(from: request)
        if !(200...299).contains(status) {
            throw SonosError.httpStatus(status)
        }
        return data
    }

    private func dataAndStatus(from request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch let error as SonosError {
            throw error
        } catch {
            throw SonosError.unreachable
        }
    }
}
