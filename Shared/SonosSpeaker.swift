import Foundation

public struct SonosSpeaker: Identifiable, Equatable, Sendable, Codable {
    public var id: String { udn }
    public var ip: String
    public var udn: String
    public var roomName: String
    public var modelName: String
    public var modelNumber: String

    public init(ip: String, udn: String, roomName: String, modelName: String, modelNumber: String) {
        self.ip = ip
        self.udn = udn
        self.roomName = roomName
        self.modelName = modelName
        self.modelNumber = modelNumber
    }

    public var displayTitle: String {
        roomName.isEmpty ? modelName : roomName
    }

    public var displaySubtitle: String {
        let model = modelName.isEmpty ? modelNumber : modelName
        return "\(model) · \(ip)"
    }

    /// Home-theater bars that expose Night Mode and Speech Enhancement.
    /// Room names are ignored so "lamp" / "amp" / similar words cannot match.
    public var looksLikeSoundbar: Bool {
        let number = modelNumber.uppercased()
        if Self.soundbarModelNumbers.contains(number) {
            return true
        }
        return Self.containsProductName("arc", in: modelName)
            || Self.containsProductName("beam", in: modelName)
    }

    private static let soundbarModelNumbers: Set<String> = [
        "S14", // Beam
        "S17", // Beam Gen 2
        "S19", // Arc
        "S38", // Arc Ultra
        "S47"  // Arc Ultra (some firmware)
    ]

    private static func containsProductName(_ name: String, in modelName: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
        return modelName.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

public struct ArcSnapshot: Equatable, Sendable, Codable {
    public var speaker: SonosSpeaker
    public var nightMode: Bool
    public var speechEnhancement: Bool
    public var speechEQ: SpeechEQKind
    public var lastError: String?
    public var updatedAt: Date

    public init(
        speaker: SonosSpeaker,
        nightMode: Bool,
        speechEnhancement: Bool,
        speechEQ: SpeechEQKind,
        lastError: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.speaker = speaker
        self.nightMode = nightMode
        self.speechEnhancement = speechEnhancement
        self.speechEQ = speechEQ
        self.lastError = lastError
        self.updatedAt = updatedAt
    }

    public func modesEqual(_ other: ArcSnapshot) -> Bool {
        nightMode == other.nightMode
            && speechEnhancement == other.speechEnhancement
            && lastError == other.lastError
            && speaker.ip == other.speaker.ip
    }
}
