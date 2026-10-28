import AppIntents
import SwiftUI
import WidgetKit

struct ArcEntry: TimelineEntry {
    let date: Date
    let snapshot: ArcSnapshot?
}

struct ArcTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ArcEntry {
        ArcEntry(date: Date(), snapshot: .preview)
    }

    func snapshot(for configuration: ConfigureArcIntent, in context: Context) async -> ArcEntry {
        if context.isPreview {
            return ArcEntry(date: Date(), snapshot: SharedStore.load() ?? .preview)
        }
        return await entry(for: configuration)
    }

    func timeline(for configuration: ConfigureArcIntent, in context: Context) async -> Timeline<ArcEntry> {
        let item = await entry(for: configuration)
        let next = Date().addingTimeInterval(5 * 60)
        return Timeline(entries: [item], policy: .after(next))
    }

    private func entry(for configuration: ConfigureArcIntent) async -> ArcEntry {
        let stored = SharedStore.load()
        let ip = firstNonEmpty(configuration.ip, stored?.speaker.ip)
        let name = firstNonEmpty(configuration.name, stored?.speaker.displayTitle) ?? "Arc"
        guard let ip else {
            return ArcEntry(date: Date(), snapshot: stored)
        }
        if let live = await liveSnapshot(ip: ip, name: name, fallback: stored) {
            return ArcEntry(date: Date(), snapshot: live)
        }
        return ArcEntry(date: Date(), snapshot: stored)
    }

    private func liveSnapshot(ip: String, name: String, fallback: ArcSnapshot?) async -> ArcSnapshot? {
        let client = SonosSOAPClient(timeout: 3)
        let speaker = (try? await client.fetchSpeaker(ip: ip))
            ?? fallback?.speaker
            ?? SonosSpeaker(ip: ip, udn: "uuid:\(ip)", roomName: name, modelName: "Sonos", modelNumber: "")
        let eq = fallback?.speechEQ ?? .dialogLevel
        guard let state = try? await client.pollHomeTheater(ip: ip, speechEQ: eq) else {
            return fallback
        }
        return ArcSnapshot(
            speaker: speaker,
            nightMode: state.night,
            speechEnhancement: state.speech,
            speechEQ: state.speechEQ
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

struct ArcWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ArcEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            configured(snapshot)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sonos Arc")
                    .font(.headline)
                Text("Hold this widget, tap Edit Widget, and enter the Arc IP from the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .widgetChrome()
        }
    }

    @ViewBuilder
    private func configured(_ snapshot: ArcSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.speaker.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if snapshot.lastError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                ModeIntentButton(
                    title: "Night",
                    systemImage: "moon.fill",
                    isOn: snapshot.nightMode,
                    intent: SetNightModeIntent(on: !snapshot.nightMode, ip: snapshot.speaker.ip)
                )
                ModeIntentButton(
                    title: "Speech",
                    systemImage: "waveform",
                    isOn: snapshot.speechEnhancement,
                    intent: SetSpeechIntent(on: !snapshot.speechEnhancement, ip: snapshot.speaker.ip)
                )
            }
            if family != .systemSmall, let error = snapshot.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .widgetChrome()
    }
}

private struct ModeIntentButton<Intent: AppIntent>: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let intent: Intent

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(isOn ? "\(title) on" : title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 6)
            .background(isOn ? Color.orange : Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func widgetChrome() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
            .tint(.orange)
    }
}

extension ArcSnapshot {
    static var preview: ArcSnapshot {
        ArcSnapshot(
            speaker: SonosSpeaker(
                ip: "192.168.1.50",
                udn: "uuid:RINCON_PREVIEW",
                roomName: "Living Room",
                modelName: "Sonos Arc",
                modelNumber: "S19"
            ),
            nightMode: true,
            speechEnhancement: false,
            speechEQ: .dialogLevel
        )
    }
}

struct ArcWidget: Widget {
    let kind = WidgetKind.arc

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigureArcIntent.self, provider: ArcTimelineProvider()) { entry in
            ArcWidgetView(entry: entry)
        }
        .configurationDisplayName("Night and Speech")
        .description("Night Mode and Speech Enhancement for your Sonos Arc.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
