import AppIntents
import WidgetKit

struct ConfigureArcIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Sonos speaker"
    static var description = IntentDescription("Which speaker the widget controls.")
    static var isDiscoverable = false

    @Parameter(title: "Speaker IP")
    var ip: String?

    @Parameter(title: "Name")
    var name: String?

    init() {
        let stored = SharedStore.load()
        ip = stored?.speaker.ip
        name = stored?.speaker.displayTitle
    }

    init(ip: String?, name: String?) {
        self.ip = ip
        self.name = name
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Control \(\.$name)")
    }
}
