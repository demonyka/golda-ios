import Foundation
import GoldaCore

/// Gemini over its REST API, the port of Android's `Gemini` object: the same endpoint, the same
/// request (system prompt, the audio inline, `VoicePrompt.schema` as the response schema) and the
/// same reading of the answer. The key is read from [secrets] on every call, so a key entered in the
/// settings works for the next note without rebuilding anything.
public struct GeminiProvider: VoiceProvider {
    private let secrets: any SecretStore
    private let transport: any HTTPTransport

    public init(secrets: any SecretStore, transport: any HTTPTransport = URLSessionTransport()) {
        self.secrets = secrets
        self.transport = transport
    }

    public static func endpoint(model: String) -> URL {
        // `appending(path:)` escapes what a hand-typed model name may contain (a space) and keeps
        // the colon, which a path segment allows.
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/")!.appending(path: "\(model):generateContent")
    }

    public func parse(audio: URL, system: String, model: String) async throws -> VoiceResult {
        guard let key = secrets.read(SecretKey.gemini) else { throw VoiceProviderError.noKey }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: audio)
        } catch {
            // Android read the file inside the catch for network errors, so an unreadable note
            // waits. That is right on iOS too: a protected file cannot be read while the phone is
            // locked and can be later.
            throw VoiceProviderError.offline(message: String(describing: error))
        }

        var request = URLRequest(url: Self.endpoint(model: model))
        request.httpMethod = "POST"
        // Android allowed 15 s to connect and 45 s to read. URLRequest has one limit, on silence,
        // which covers both; the longer one keeps a slow answer from being cut off.
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try Self.body(audio: bytes, mime: Self.mime(of: audio), system: system)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw VoiceProviderError.offline(message: String(describing: error))
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = Self.errorMessage(data) ?? "HTTP \(response.statusCode)"
            // A server error passes; a refusal (bad key, unknown model, quota) needs a person.
            throw response.statusCode >= 500 ? VoiceProviderError.offline(message: message) : .rejected(message: message)
        }
        return try Self.read(data)
    }

    /// What Gemini is told the audio is, by the file's extension, as on Android.
    static func mime(of audio: URL) -> String {
        switch audio.pathExtension {
        case "wav": "audio/wav"
        case "aac": "audio/aac"
        case "m4a": "audio/mp4"
        default: "audio/ogg"
        }
    }

    static func body(audio: Data, mime: String, system: String) throws -> Data {
        let schema = try JSONSerialization.jsonObject(with: Data(VoicePrompt.schema.utf8))
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["parts": [["inlineData": ["mimeType": mime, "data": audio.base64EncodedString()]]]]],
            "generationConfig": ["responseMimeType": "application/json", "responseSchema": schema],
        ]
        // Sorted keys keep the body the same from run to run; unescaped slashes keep the base64 short.
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// `error.message` of Google's error answer, when there is one.
    static func errorMessage(_ data: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return scalar((root?["error"] as? [String: Any])?["message"])
    }

    /// The first part's text of the first candidate, read as the schema's object. Android's
    /// `Gemini.read`: an optional field that is missing, null or blank is nil; a missing
    /// transcript or note is empty; a missing intent is "unknown"; no items is none.
    static func read(_ data: Data) throws -> VoiceResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidate = (root["candidates"] as? [Any])?.first as? [String: Any],
              let part = ((candidate["content"] as? [String: Any])?["parts"] as? [Any])?.first as? [String: Any],
              let text = scalar(part["text"]),
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { throw VoiceProviderError.malformedAnswer }

        let items = json["items"] as? [Any] ?? []
        return VoiceResult(
            transcript: scalar(json["transcript"]) ?? "",
            items: try items.map { element in
                // Android's `getJSONObject(i)` threw on anything else.
                guard let item = element as? [String: Any] else { throw VoiceProviderError.malformedAnswer }
                func optional(_ name: String) -> String? {
                    scalar(item[name]).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                }
                return VoiceItem(
                    intent: scalar(item["intent"]) ?? "unknown",
                    amount: optional("amount"),
                    currency: optional("currency"),
                    note: scalar(item["note"]) ?? "",
                    category: optional("category"),
                    accountId: optional("account_id"),
                    toAccountId: optional("to_account_id"),
                    toAmount: optional("to_amount"),
                    date: optional("date")
                )
            }
        )
    }

    /// A string as is, a number as its text (org.json's `getString` coerced a model that answered
    /// `15` instead of `"15"`), nil for null, a missing value or anything else.
    private static func scalar(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }
}
