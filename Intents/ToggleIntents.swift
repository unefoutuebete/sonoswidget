import AppIntents

struct SetNightModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Night Mode"
    static var description = IntentDescription("Turn Night Mode on or off for the Sonos Arc.")
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @Parameter(title: "On")
    var on: Bool?

    @Parameter(title: "Speaker IP")
    var ip: String?

    init() {}

    init(on: Bool, ip: String) {
        self.on = on
        self.ip = ip
    }

    func perform() async throws -> some IntentResult {
        guard let on else { return .result() }
        await ArcController().setNightMode(on, ip: ip)
        return .result()
    }
}

struct SetSpeechIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Speech Enhancement"
    static var description = IntentDescription("Turn Speech Enhancement on or off for the Sonos Arc.")
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @Parameter(title: "On")
    var on: Bool?

    @Parameter(title: "Speaker IP")
    var ip: String?

    init() {}

    init(on: Bool, ip: String) {
        self.on = on
        self.ip = ip
    }

    func perform() async throws -> some IntentResult {
        guard let on else { return .result() }
        await ArcController().setSpeechEnhancement(on, ip: ip)
        return .result()
    }
}

struct ToggleNightModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Night Mode"
    static var isDiscoverable = true

    func perform() async throws -> some IntentResult {
        let current = SharedStore.load()?.nightMode ?? false
        await ArcController().setNightMode(!current)
        return .result()
    }
}

struct ToggleSpeechIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Speech Enhancement"
    static var isDiscoverable = true

    func perform() async throws -> some IntentResult {
        let current = SharedStore.load()?.speechEnhancement ?? false
        await ArcController().setSpeechEnhancement(!current)
        return .result()
    }
}
