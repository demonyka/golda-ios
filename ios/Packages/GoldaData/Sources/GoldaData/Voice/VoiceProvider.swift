import Foundation
import GoldaCore

/// Turns a recorded note into what was said. Only extracts: amounts, rates and accounts are worked
/// out afterwards by `VoiceMapper`. Version 1 has one provider, Gemini (D8); tests use a stub.
public protocol VoiceProvider: Sendable {
    /// [system] is `VoicePrompt.system` for the note's profile; [model] the model this phone is set
    /// to. Throws `VoiceProviderError`; any other error is treated as a lost connection.
    func parse(audio: URL, system: String, model: String) async throws -> VoiceResult
}

/// Android's `GeminiException(message, offline)`, with the cases the service tells apart.
public enum VoiceProviderError: Error, Equatable, Sendable {
    /// No API key is stored; the note waits for one.
    case noKey
    /// No network, a timeout, an unreadable file or the service failing on its side (5xx): worth
    /// trying again later. [message] is for logs only.
    case offline(message: String)
    /// The service refused the note (4xx); [message] is its own explanation, or "HTTP <code>".
    case rejected(message: String)
    /// The answer was not the JSON the schema asks for.
    case malformedAnswer
    /// The service does not work where the phone is (Gemini in Russia without a VPN); the note can be
    /// understood later, from somewhere it does.
    case unsupportedLocation
}
