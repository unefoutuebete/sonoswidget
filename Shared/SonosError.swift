import Foundation

public enum SonosError: Error, LocalizedError, Equatable {
    case invalidURL
    case unreachable
    case soapFault(String)
    case parse
    case unsupportedSpeaker
    case noSpeakerSelected
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid speaker address."
        case .unreachable:
            return "Could not reach the speaker on Wi-Fi."
        case .soapFault(let message):
            return message
        case .parse:
            return "Unexpected response from the speaker."
        case .unsupportedSpeaker:
            return "This speaker does not support Night Mode or Speech Enhancement."
        case .noSpeakerSelected:
            return "No speaker selected."
        case .httpStatus(let code):
            return "Speaker returned HTTP \(code)."
        }
    }
}
