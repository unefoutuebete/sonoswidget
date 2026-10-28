import AppIntents
import SwiftUI

@main
struct SonosArcApp: App {
    @StateObject private var session = ArcSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onAppear { session.handleScenePhase(.active) }
        }
        .onChange(of: scenePhase) { _, phase in
            session.handleScenePhase(phase)
        }
    }
}

struct SonosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleNightModeIntent(),
            phrases: [
                "Toggle Night Mode in \(.applicationName)",
                "Turn on Night Mode in \(.applicationName)"
            ],
            shortTitle: "Night Mode",
            systemImageName: "moon.fill"
        )
        AppShortcut(
            intent: ToggleSpeechIntent(),
            phrases: [
                "Toggle Speech Enhancement in \(.applicationName)"
            ],
            shortTitle: "Speech Enhancement",
            systemImageName: "waveform"
        )
    }
}
