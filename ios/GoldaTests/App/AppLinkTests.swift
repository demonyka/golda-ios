import Foundation
import Testing

@testable import Golda

/// The links the widgets open: `golda://new` is the toolbar's "+", `golda://home` a tap beside the
/// buttons, `golda://voice` the mic (`VoiceEntry`). The tabs follow the first two once they are on
/// screen, the way they take a voice note asked for from outside.
@MainActor @Suite struct AppLinkTests {
    // MARK: Which link is which

    @Test func eachLinkReadsBackAsItself() {
        for link in [AppLink.voice, .newOperation, .home] {
            #expect(AppLink(link.url) == link, "\(link)")
        }
        #expect(AppLink.voice.url == VoiceEntry.url)
        #expect(AppLink.newOperation.url.absoluteString == "golda://new")
        #expect(AppLink.home.url.absoluteString == "golda://home")
    }

    /// Schemes and hosts are case-insensitive; a trailing slash is the same link.
    @Test func caseAndATrailingSlashDoNotMatter() throws {
        #expect(AppLink(try #require(URL(string: "GOLDA://New/"))) == .newOperation)
        #expect(AppLink(try #require(URL(string: "golda://HOME"))) == .home)
        #expect(AppLink(try #require(URL(string: "Golda://voice/"))) == .voice)
    }

    @Test func otherLinksAreNotTheWidgets() throws {
        for other in ["golda://settings", "golda://", "https://new", "new://golda", "golda:new", "golda://newer"] {
            #expect(AppLink(try #require(URL(string: other))) == nil, "\(other)")
        }
    }

    // MARK: Following a link

    @Test func theVoiceLinkAsksTheMicForANote() throws {
        let voice = VoiceEntryRequests.shared
        let links = AppLinkRequests()
        defer { voice.discard() }
        voice.discard()

        #expect(links.open(AppLink.voice.url))
        #expect(voice.isPending)
        #expect(links.pending == nil)
        #expect(!links.open(try #require(URL(string: "golda://settings"))))
    }

    @Test func plusOpensTheNewOperationFormOverTheTabs() {
        let links = AppLinkRequests()
        #expect(links.open(AppLink.newOperation.url))

        #expect(links.take(over: nil) == .newOperation)
        #expect(links.pending == nil)
        #expect(links.take(over: nil) == nil)
    }

    /// A screen over the tabs keeps what is typed in it, as for a voice note: the form opens once it
    /// closes. A form for a new operation already open is what was asked for.
    @Test func plusWaitsForTheScreenOverTheTabs() {
        let links = AppLinkRequests()
        links.post(.newOperation)

        #expect(links.take(over: .settings) == nil)
        #expect(links.take(over: .entry(EntryRequest(editing: nil))) == nil)
        #expect(links.pending == nil)

        links.post(.newOperation)
        #expect(links.take(over: .profiles) == nil)
        #expect(links.pending == .newOperation)
        #expect(links.take(over: nil) == .newOperation)
    }

    @Test func aTapBesideTheButtonsShowsHome() {
        let links = AppLinkRequests()
        links.post(.home)

        #expect(links.take(over: .settings) == .showHome)
        #expect(links.pending == nil)
    }

    /// The newer link wins, as a second tap on the widget means the second thing.
    @Test func theNewerLinkWins() {
        let links = AppLinkRequests()
        links.post(.newOperation)
        links.post(.home)

        #expect(links.take(over: nil) == .showHome)
        #expect(links.take(over: nil) == nil)
    }
}
