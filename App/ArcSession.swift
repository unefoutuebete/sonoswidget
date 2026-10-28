import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class ArcSession: ObservableObject {
    @Published var snapshot: ArcSnapshot?
    @Published var speakers: [SonosSpeaker] = []
    @Published var isDiscovering = false
    @Published var isWorking = false
    @Published var message: String?
    @Published var manualIP = ""
    @Published var lastPollError: String?

    private let controller = ArcController()
    private let discovery = SonosDiscovery()
    private var pollTask: Task<Void, Never>?
    private var isPolling = false

    init() {
        snapshot = SharedStore.load()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            startPolling()
        default:
            stopPolling()
        }
    }

    func appear() async {
        snapshot = SharedStore.load()
        guard snapshot != nil else { return }
        await poll(force: true)
    }

    func discover() async {
        isDiscovering = true
        message = "Looking for Sonos on Wi-Fi…"
        defer { isDiscovering = false }
        let found = await discovery.discover()
        speakers = found
        if found.isEmpty {
            message = "No speakers found. Stay on the same Wi-Fi as Sonos, then try an IP."
        } else {
            message = "Found \(found.count) speaker\(found.count == 1 ? "" : "s")."
        }
    }

    func connect(to speaker: SonosSpeaker) async {
        await run {
            let next = try await controller.select(speaker)
            snapshot = next
            message = widgetMessage(for: next, prefix: "Using \(next.speaker.displayTitle).")
        }
        startPolling()
    }

    func connectToManualIP() async {
        let ip = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else { return }
        await run {
            let speaker = try await discovery.speaker(at: ip)
            let next = try await controller.select(speaker)
            snapshot = next
            if !speakers.contains(speaker) {
                speakers.insert(speaker, at: 0)
            }
            message = widgetMessage(for: next, prefix: "Using \(next.speaker.displayTitle).")
        }
        startPolling()
    }

    func refresh(resolvingIP: Bool = true) async {
        await run {
            snapshot = try await resolvingIP ? controller.refresh() : controller.poll()
            lastPollError = nil
        }
    }

    func poll(force: Bool = false) async {
        guard snapshot != nil else { return }
        guard force || !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        do {
            let previous = snapshot
            let next = try await controller.poll()
            snapshot = next
            lastPollError = nil
            if previous.map({ !$0.modesEqual(next) }) ?? true {
                reloadWidget()
            }
        } catch {
            lastPollError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setNightMode(_ on: Bool) async {
        guard var next = snapshot else { return }
        next.nightMode = on
        snapshot = next
        await ArcController().setNightMode(on)
        snapshot = SharedStore.load()
        reloadWidget()
    }

    func setSpeech(_ on: Bool) async {
        guard var next = snapshot else { return }
        next.speechEnhancement = on
        snapshot = next
        await ArcController().setSpeechEnhancement(on)
        snapshot = SharedStore.load()
        reloadWidget()
    }

    func publishToWidget() {
        guard let snapshot else { return }
        SharedStore.save(snapshot)
        reloadWidget()
        message = widgetMessage(for: snapshot, prefix: "Widget updated.")
    }

    func forgetSpeaker() {
        stopPolling()
        SharedStore.clear()
        snapshot = nil
        lastPollError = nil
        message = "Choose a speaker to control from the widget."
        reloadWidget()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            await self?.appear()
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self.poll()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            reloadWidget()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            snapshot = SharedStore.load()
        }
    }

    private func widgetMessage(for snapshot: ArcSnapshot, prefix: String) -> String {
        var parts = [prefix]
        if !snapshot.speaker.looksLikeSoundbar {
            parts.append("This model may not support Night Mode or Speech Enhancement.")
        }
        parts.append("Add the Night and Speech widget, then if it is empty hold it and choose Edit Widget. Enter speaker IP \(snapshot.speaker.ip).")
        return parts.joined(separator: " ")
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.arc)
    }
}
