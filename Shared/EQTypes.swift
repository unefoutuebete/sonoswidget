import Foundation

public enum HomeTheaterEQ: String, Codable, Sendable, CaseIterable {
    case nightMode = "NightMode"
    case dialogLevel = "DialogLevel"
    case speechEnhanceEnabled = "SpeechEnhanceEnabled"
}

public enum SpeechEQKind: String, Codable, Sendable {
    case dialogLevel
    case speechEnhanceEnabled

    public var eq: HomeTheaterEQ {
        switch self {
        case .dialogLevel: return .dialogLevel
        case .speechEnhanceEnabled: return .speechEnhanceEnabled
        }
    }
}
