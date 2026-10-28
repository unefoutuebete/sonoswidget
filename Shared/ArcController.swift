import Foundation

public struct ArcController: Sendable {
    private let client: SonosSOAPClient
    private let discovery: SonosDiscovery

    public init(
        client: SonosSOAPClient = SonosSOAPClient(),
        discovery: SonosDiscovery = SonosDiscovery()
    ) {
        self.client = client
        self.discovery = discovery
    }

    public func snapshot() -> ArcSnapshot? {
        SharedStore.load()
    }

    public func refresh() async throws -> ArcSnapshot {
        guard let current = SharedStore.load() else {
            throw SonosError.noSpeakerSelected
        }
        let speaker = await discovery.resolve(udn: current.speaker.udn, fallbackIP: current.speaker.ip)
            ?? current.speaker
        let next = try await client.loadSnapshot(for: speaker)
        SharedStore.save(next)
        return next
    }

    public func poll() async throws -> ArcSnapshot {
        guard var current = SharedStore.load() else {
            throw SonosError.noSpeakerSelected
        }
        let state = try await client.pollHomeTheater(ip: current.speaker.ip, speechEQ: current.speechEQ)
        current.nightMode = state.night
        current.speechEnhancement = state.speech
        current.speechEQ = state.speechEQ
        current.lastError = nil
        current.updatedAt = Date()
        SharedStore.save(current)
        return current
    }

    public func select(_ speaker: SonosSpeaker) async throws -> ArcSnapshot {
        let snapshot = try await client.loadSnapshot(for: speaker)
        SharedStore.save(snapshot)
        return snapshot
    }

    public func setNightMode(_ on: Bool, ip: String? = nil) async {
        guard var snapshot = resolvedSnapshot(ip: ip) else {
            rememberError(SonosError.noSpeakerSelected)
            return
        }
        do {
            try await client.setEQ(ip: snapshot.speaker.ip, type: .nightMode, on: on)
            snapshot.nightMode = on
            snapshot.lastError = nil
            snapshot.updatedAt = Date()
            SharedStore.save(snapshot)
        } catch {
            snapshot.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            SharedStore.save(snapshot)
        }
    }

    public func setSpeechEnhancement(_ on: Bool, ip: String? = nil) async {
        guard var snapshot = resolvedSnapshot(ip: ip) else {
            rememberError(SonosError.noSpeakerSelected)
            return
        }
        do {
            let kind = try await client.setSpeech(
                ip: snapshot.speaker.ip,
                on: on,
                preferred: snapshot.speechEQ
            )
            snapshot.speechEQ = kind
            snapshot.speechEnhancement = on
            snapshot.lastError = nil
            snapshot.updatedAt = Date()
            SharedStore.save(snapshot)
        } catch {
            snapshot.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            SharedStore.save(snapshot)
        }
    }

    private func resolvedSnapshot(ip: String?) -> ArcSnapshot? {
        if var snapshot = SharedStore.load() {
            if let ip, !ip.isEmpty {
                snapshot.speaker.ip = ip
            }
            return snapshot
        }
        guard let ip, !ip.isEmpty else { return nil }
        return ArcSnapshot(
            speaker: SonosSpeaker(
                ip: ip,
                udn: "uuid:\(ip)",
                roomName: ip,
                modelName: "Sonos",
                modelNumber: ""
            ),
            nightMode: false,
            speechEnhancement: false,
            speechEQ: .dialogLevel
        )
    }

    private func rememberError(_ error: SonosError) {
        guard var snapshot = SharedStore.load() else { return }
        snapshot.lastError = error.localizedDescription
        SharedStore.save(snapshot)
    }
}
