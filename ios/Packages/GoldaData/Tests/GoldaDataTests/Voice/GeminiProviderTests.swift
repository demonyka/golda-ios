import Foundation
import GoldaCore
import Synchronization
import Testing

@testable import GoldaData

/// Remembers the requests a stub transport received.
private final class SentRequests: Sendable {
    private let requests = Mutex<[URLRequest]>([])

    func record(_ request: URLRequest) { requests.withLock { $0.append(request) } }
    var all: [URLRequest] { requests.withLock { $0 } }
}

/// Gemini's answer around [inner], the text the model wrote: the first part of the first candidate.
private func envelope(_ inner: String) throws -> Data {
    let answer: [String: Any] = [
        "candidates": [["content": ["parts": [["text": inner]], "role": "model"], "finishReason": "STOP", "index": 0]],
        "usageMetadata": ["promptTokenCount": 812, "totalTokenCount": 870],
    ]
    return try JSONSerialization.data(withJSONObject: answer)
}

/// Google's error answer.
private func apiError(_ code: Int, _ message: String, _ status: String) -> Data {
    Data(#"{"error":{"code":\#(code),"message":"\#(message)","status":"\#(status)"}}"#.utf8)
}

/// The request Gemini gets and how its answers and failures are read, as Android's `Gemini` object.
@Suite final class GeminiProviderTests {
    let folder: TemporaryFolder
    let audio: URL
    let secrets = InMemorySecretStore([SecretKey.gemini: "AIza-test"])
    private let sent = SentRequests()

    init() throws {
        folder = try TemporaryFolder()
        audio = try folder.file("1759399200000.wav", [0x52, 0x49, 0x46, 0x46, 0x00, 0xFF, 0x10])
    }

    private func gemini(status: Int = 200, body: Data) -> GeminiProvider {
        let sent = sent
        return GeminiProvider(secrets: secrets, transport: StubHTTPTransport { request in
            sent.record(request)
            return (body, status)
        })
    }

    private func gemini(answer inner: String) throws -> GeminiProvider {
        gemini(body: try envelope(inner))
    }

    private func failure(_ provider: GeminiProvider) async -> VoiceProviderError? {
        do {
            _ = try await provider.parse(audio: audio, system: "", model: "gemini-3.5-flash-lite")
            return nil
        } catch {
            return error as? VoiceProviderError
        }
    }

    // MARK: Request

    @Test func theRequestIsTheOneAndroidSends() async throws {
        let provider = try gemini(answer: #"{"transcript":"","items":[]}"#)
        _ = try await provider.parse(audio: audio, system: "Ты разбираешь голосовые записи", model: "gemini-3.5-flash-lite")

        let request = try #require(sent.all.first)
        #expect(sent.all.count == 1)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // The key travels in the header, never in the address.
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")
        #expect(request.url?.query == nil)
        #expect(request.timeoutInterval == 45)

        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? NSDictionary
        let schema = try JSONSerialization.jsonObject(with: Data(VoicePrompt.schema.utf8))
        // Android's JSONObject, field by field.
        let android: NSDictionary = [
            "systemInstruction": ["parts": [["text": "Ты разбираешь голосовые записи"]]],
            "contents": [["parts": [["inlineData": ["mimeType": "audio/wav", "data": "UklGRgD/EA=="]]]]],
            "generationConfig": ["responseMimeType": "application/json", "responseSchema": schema],
        ]
        #expect(body == android)
    }

    @Test func theResponseSchemaIsTheDomainsSchema() async throws {
        let provider = try gemini(answer: #"{"transcript":"","items":[]}"#)
        _ = try await provider.parse(audio: audio, system: "", model: "gemini-3.5-flash-lite")
        let sentBody = try #require(sent.all.first?.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        let config = try #require(body["generationConfig"] as? [String: Any])
        let schema = try #require(config["responseSchema"] as? [String: Any])
        let item = try #require(((schema["properties"] as? [String: Any])?["items"] as? [String: Any])?["items"] as? [String: Any])
        #expect((item["required"] as? [String]) == ["intent", "note"])
        #expect(((item["properties"] as? [String: Any])?["amount"] as? [String: Any])?["nullable"] as? Bool == true)
    }

    @Test(arguments: [
        ("1.wav", "audio/wav"), ("1.aac", "audio/aac"), ("1.m4a", "audio/mp4"), ("1.ogg", "audio/ogg"), ("1.mp3", "audio/ogg"),
    ])
    func theMimeTypeFollowsTheExtension(name: String, mime: String) {
        #expect(GeminiProvider.mime(of: URL(fileURLWithPath: "/voice/\(name)")) == mime)
    }

    @Test func theModelIsPartOfTheAddress() {
        #expect(GeminiProvider.endpoint(model: "gemini-2.5-flash").absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        // A hand-typed name with a space still makes an address; Gemini answers that it has no such model.
        #expect(GeminiProvider.endpoint(model: "my model").absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/my%20model:generateContent")
    }

    @Test func withoutAKeyNothingIsSent() async {
        try? secrets.delete(SecretKey.gemini)
        let provider = gemini(body: Data())
        #expect(await failure(provider) == .noKey)
        #expect(sent.all.isEmpty)
    }

    @Test func aNoteThatCannotBeReadWaits() async throws {
        let provider = try gemini(answer: "{}")
        try FileManager.default.removeItem(at: audio)
        guard case .offline = await failure(provider) else {
            Issue.record("an unreadable note must wait, as Android's IOException did")
            return
        }
        #expect(sent.all.isEmpty)
    }

    // MARK: Answer

    @Test func severalItemsWithNullAndBlankFields() async throws {
        let provider = try gemini(answer: #"""
        {"transcript":"Кофе 8 лари и такси 15, ой, вчера","items":[
          {"intent":"expense","amount":"8","currency":"GEL","note":"кофе","category":"eating_out",
           "account_id":null,"to_account_id":null,"to_amount":null,"date":null},
          {"intent":"expense","amount":"15","currency":"  ","note":"такси","category":"","account_id":"2","date":"2026-10-01"},
          {"intent":"transfer","amount":"100","currency":"USD","note":"","account_id":"2","to_account_id":"3","to_amount":"8300"},
          {"note":"что-то"}
        ]}
        """#)
        let result = try await provider.parse(audio: audio, system: "", model: "gemini-3.5-flash-lite")
        #expect(result == VoiceResult(transcript: "Кофе 8 лари и такси 15, ой, вчера", items: [
            VoiceItem(intent: "expense", amount: "8", currency: "GEL", note: "кофе", category: "eating_out"),
            VoiceItem(intent: "expense", amount: "15", note: "такси", accountId: "2", date: "2026-10-01"),
            VoiceItem(intent: "transfer", amount: "100", currency: "USD", note: "", accountId: "2", toAccountId: "3", toAmount: "8300"),
            // A missing intent is "unknown", a missing optional field nil.
            VoiceItem(intent: "unknown", note: "что-то"),
        ]))
    }

    @Test func missingTranscriptAndItemsAreEmpty() async throws {
        let result = try await gemini(answer: "{}").parse(audio: audio, system: "", model: "m")
        #expect(result == VoiceResult(transcript: "", items: []))
        let notAnArray = try await gemini(answer: #"{"transcript":"тишина","items":"none"}"#).parse(audio: audio, system: "", model: "m")
        #expect(notAnArray == VoiceResult(transcript: "тишина", items: []))
    }

    @Test func aNumberWhereTextWasAskedIsReadAsText() async throws {
        // org.json's getString coerced numbers; a model that ignores the schema still books.
        let result = try await gemini(answer: #"{"transcript":"x","items":[{"intent":"expense","amount":15,"to_amount":1500.5,"note":"кофе"}]}"#)
            .parse(audio: audio, system: "", model: "m")
        #expect(result.items == [VoiceItem(intent: "expense", amount: "15", note: "кофе", toAmount: "1500.5")])
    }

    @Test(arguments: [
        #"{"promptFeedback":{"blockReason":"SAFETY"}}"#,
        #"{"candidates":[]}"#,
        #"{"candidates":[{"finishReason":"SAFETY"}]}"#,
        "not json",
    ])
    func anAnswerWithoutTheModelsTextIsMalformed(body: String) async {
        #expect(await failure(gemini(body: Data(body.utf8))) == .malformedAnswer)
    }

    @Test(arguments: ["not json", "[1, 2]", #"{"transcript":"x","items":["кофе"]}"#])
    func textThatIsNotTheSchemasObjectIsMalformed(inner: String) async throws {
        #expect(await failure(try gemini(answer: inner)) == .malformedAnswer)
    }

    // MARK: Failures

    @Test func aRefusalCarriesTheAPIsOwnMessage() async {
        let body = apiError(400, "API key not valid. Please pass a valid API key.", "INVALID_ARGUMENT")
        #expect(await failure(gemini(status: 400, body: body)) == .rejected(message: "API key not valid. Please pass a valid API key."))
    }

    @Test func aRefusalWithoutAMessageNamesTheStatus() async {
        #expect(await failure(gemini(status: 404, body: Data("<html>Not Found</html>".utf8))) == .rejected(message: "HTTP 404"))
        #expect(await failure(gemini(status: 403, body: Data())) == .rejected(message: "HTTP 403"))
    }

    @Test func tooManyRequestsIsARefusalNotAnOutage() async {
        // Android: only 5xx and network errors are offline.
        let body = apiError(429, "Resource has been exhausted (e.g. check quota).", "RESOURCE_EXHAUSTED")
        #expect(await failure(gemini(status: 429, body: body)) == .rejected(message: "Resource has been exhausted (e.g. check quota)."))
    }

    @Test func aServerErrorIsOffline() async {
        #expect(await failure(gemini(status: 500, body: Data())) == .offline(message: "HTTP 500"))
        let overloaded = apiError(503, "The model is overloaded. Please try again later.", "UNAVAILABLE")
        #expect(await failure(gemini(status: 503, body: overloaded)) == .offline(message: "The model is overloaded. Please try again later."))
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost])
    func aNetworkErrorIsOffline(code: URLError.Code) async {
        let provider = GeminiProvider(secrets: secrets, transport: StubHTTPTransport(error: URLError(code)))
        guard case .offline = await failure(provider) else {
            Issue.record("\(code) must count as offline")
            return
        }
    }
}
