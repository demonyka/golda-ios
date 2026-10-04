import Foundation
import Testing

@testable import Golda

/// The ways into a voice note from outside the app, the port of Android's `ACTION_VOICE`: the
/// widget's link, the quick action on the icon and `StartVoiceNoteIntent` (Control Center, the
/// Action Button, Siri, Spotlight) all become one request, which starts a note as a tap on the mic
/// does once the mic is on screen.
@MainActor @Suite struct VoiceEntryTests {
    // MARK: What asks for a note

    @Test func theVoiceLinkAsksForANote() throws {
        #expect(VoiceEntry.isRequest(VoiceEntry.url))
        #expect(VoiceEntry.isRequest(try #require(URL(string: "golda://voice"))))
        #expect(VoiceEntry.isRequest(try #require(URL(string: "GOLDA://Voice/"))))
        for other in ["golda://settings", "golda://", "https://voice", "voice://golda", "golda:voice"] {
            #expect(!VoiceEntry.isRequest(try #require(URL(string: other))), "\(other)")
        }
    }

    @Test func theQuickActionAsksForANote() {
        #expect(VoiceEntry.isRequest(shortcutType: VoiceEntry.shortcutType))
        #expect(!VoiceEntry.isRequest(shortcutType: "com.f4studio.golda.other"))
        #expect(!VoiceEntry.isRequest(shortcutType: ""))
    }

    /// The app claims the scheme of the widget's link, so the system hands the link to it.
    @Test func theAppOpensItsOwnScheme() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(try #require(VoiceEntry.url.scheme)))
    }

    /// The quick action on the icon is in Info.plist from the install on, with the type the app answers.
    @Test func theIconCarriesTheQuickAction() throws {
        let items = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        let item = try #require(items.first { $0["UIApplicationShortcutItemType"] as? String == VoiceEntry.shortcutType })
        #expect(item["UIApplicationShortcutItemIconSymbolName"] as? String == Symbols.mic)
        let title = try #require(item["UIApplicationShortcutItemTitle"] as? String)
        // The system looks the title up in InfoPlist.strings by its value.
        for language in ["en", "ru"] {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let localized = Bundle(path: path)?.localizedString(forKey: title, value: "∅", table: "InfoPlist")
            #expect(localized != "∅", "\(language)")
        }
    }

    @Test func theIntentAsksForANote() async throws {
        let requests = VoiceEntryRequests.shared
        defer { requests.discard() }
        requests.discard()
        _ = try await StartVoiceNoteIntent().perform()
        #expect(requests.isPending)
    }

    /// Siri takes a phrase only with the app's name in it, in every language.
    @Test func everySiriPhraseNamesTheApp() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Golda/Resources/AppShortcuts.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let phrases = try #require(json?["strings"] as? [String: [String: Any]])
        #expect(phrases.count == 3)
        for (key, entry) in phrases {
            #expect(key.contains("${applicationName}"), "\(key)")
            let localizations = entry["localizations"] as? [String: [String: [String: String]]] ?? [:]
            for language in ["en", "ru"] {
                let value = localizations[language]?["stringUnit"]?["value"] ?? ""
                #expect(value.contains("${applicationName}"), "\(key) \(language): \(value)")
            }
        }
    }

    // MARK: The handoff

    @Test func aRequestStartsTheNoteOnce() {
        let requests = VoiceEntryRequests()
        let mic = StubMicModel()
        requests.deliver(to: mic, sceneIsActive: true, micIsCovered: false)
        #expect(mic.state == .idle, "nothing asked")

        // The widget tapped twice before the app came up is still one note.
        requests.post()
        requests.post()
        #expect(requests.isPending)
        requests.deliver(to: mic, sceneIsActive: true, micIsCovered: false)
        #expect(mic.state == .recording)
        #expect(!requests.isPending)
        requests.deliver(to: mic, sceneIsActive: true, micIsCovered: false)
        #expect(mic.state == .recording)
    }

    /// The microphone records only in the foreground: the request waits for the scene to be active.
    @Test func aRequestWaitsForTheForeground() {
        let requests = VoiceEntryRequests()
        let mic = StubMicModel()
        requests.post()
        requests.deliver(to: mic, sceneIsActive: false, micIsCovered: false)
        #expect(mic.state == .idle)
        #expect(requests.isPending)
        requests.deliver(to: mic, sceneIsActive: true, micIsCovered: false)
        #expect(mic.state == .recording)
    }

    /// A form over the tabs keeps what is typed in it: the note starts once it is closed and the
    /// mic shows, as the screens the voice asks for wait (`MicPlacement`).
    @Test func aRequestWaitsForTheScreenOverTheMic() {
        let requests = VoiceEntryRequests()
        let mic = StubMicModel()
        requests.post()
        requests.deliver(to: mic, sceneIsActive: true, micIsCovered: true)
        #expect(mic.state == .idle)
        #expect(requests.isPending)
        requests.deliver(to: mic, sceneIsActive: true, micIsCovered: false)
        #expect(mic.state == .recording)
    }

    /// As on Android, only an idle mic starts: a request never stops the note being recorded or
    /// interrupts one being worked out, and it is used up.
    @Test func aRequestLeavesABusyMicAlone() {
        let requests = VoiceEntryRequests()
        let mic = StubMicModel()
        mic.tap()
        requests.post()
        requests.deliver(to: mic, sceneIsActive: true, micIsCovered: false)
        #expect(mic.state == .recording)
        #expect(!requests.isPending)

        mic.tap()
        requests.post()
        requests.deliver(to: mic, sceneIsActive: true, micIsCovered: false)
        #expect(mic.state == .thinking)
        #expect(!requests.isPending)
    }

    /// Before consent the request opens the consent screen, exactly as the first tap does; agreeing
    /// starts the recording it asked for.
    @Test func withoutConsentARequestAsksFirst() async throws {
        let h = try MicHarness()
        try await h.open(consent: false)
        let requests = VoiceEntryRequests()

        requests.post()
        requests.deliver(to: h.mic, sceneIsActive: true, micIsCovered: false)
        #expect(h.mic.route == .voiceConsent)
        #expect(h.recorder.started.isEmpty)

        h.mic.route = nil
        h.mic.answerConsent(true)
        #expect(h.mic.state == .recording)
        #expect(h.recorder.started.count == 1)
    }

    @Test func withConsentARequestRecords() async throws {
        let h = try MicHarness()
        try await h.open()
        let requests = VoiceEntryRequests()

        requests.post()
        requests.deliver(to: h.mic, sceneIsActive: true, micIsCovered: false)
        #expect(h.mic.state == .recording)
        #expect(h.recorder.started.count == 1)
    }
}
