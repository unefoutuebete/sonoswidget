import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: ArcSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let snapshot = session.snapshot {
                        speakerCard(snapshot)
                        modeCard(snapshot)
                    } else {
                        emptyCard
                    }
                    discoveryCard
                    if let message = session.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sonos Arc")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if session.snapshot != nil {
                        Button("Refresh") {
                            Task { await session.refresh() }
                        }
                        .disabled(session.isWorking)
                    }
                }
            }
        }
    }

    private func speakerCard(_ snapshot: ArcSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Selected speaker", systemImage: "hifispeaker.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(snapshot.speaker.displayTitle)
                .font(.title2.weight(.semibold))
            Text(snapshot.speaker.displaySubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Widget IP \(snapshot.speaker.ip)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Last checked \(snapshot.updatedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let error = snapshot.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let pollError = session.lastPollError {
                Text("Poll: \(pollError)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button("Use this speaker on the widget") {
                session.publishToWidget()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Button("Choose a different speaker", role: .destructive) {
                session.forgetSpeaker()
            }
            .padding(.top, 4)
        }
        .card()
    }

    private func modeCard(_ snapshot: ArcSnapshot) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: nightBinding(snapshot)) {
                Label("Night Mode", systemImage: "moon.fill")
            }
            .padding(.vertical, 6)
            Divider()
            Toggle(isOn: speechBinding(snapshot)) {
                Label("Speech Enhancement", systemImage: "waveform")
            }
            .padding(.vertical, 6)
        }
        .card()
        .disabled(session.isWorking)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Control Night Mode and Speech Enhancement from a Home Screen widget.")
            Text("Pick your Arc or Beam, then tap Use this speaker on the widget.")
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find speaker")
                .font(.headline)
            Button {
                Task { await session.discover() }
            } label: {
                HStack {
                    if session.isDiscovering {
                        ProgressView()
                    }
                    Text(session.isDiscovering ? "Scanning Wi-Fi…" : "Discover Sonos")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isDiscovering)

            HStack {
                TextField("Or enter IP, like 192.168.1.50", text: $session.manualIP)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Button("Connect") {
                    Task { await session.connectToManualIP() }
                }
                .disabled(session.manualIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ForEach(session.speakers) { speaker in
                Button {
                    Task { await session.connect(to: speaker) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(speaker.displayTitle)
                                .font(.body.weight(.medium))
                            Text(speaker.displaySubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if speaker.looksLikeSoundbar {
                            Text("Soundbar")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .card()
    }

    private func nightBinding(_ snapshot: ArcSnapshot) -> Binding<Bool> {
        Binding(
            get: { snapshot.nightMode },
            set: { newValue in
                Task { await session.setNightMode(newValue) }
            }
        )
    }

    private func speechBinding(_ snapshot: ArcSnapshot) -> Binding<Bool> {
        Binding(
            get: { snapshot.speechEnhancement },
            set: { newValue in
                Task { await session.setSpeech(newValue) }
            }
        )
    }
}

private extension View {
    func card() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
