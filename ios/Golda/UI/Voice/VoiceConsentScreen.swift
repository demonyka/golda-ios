import SwiftUI

/// Asks before the first voice note goes to Google Gemini (D9, App Review 5.1.2(i)): who gets it,
/// what exactly leaves the phone, with whose key, and how to take it back. "Согласен" keeps the
/// answer on this phone and starts the recording the mic was tapped for; "Не сейчас", or pulling
/// the sheet down, leaves voice off and nothing is sent.
struct VoiceConsentScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.voiceConsent) private var consent
    @State private var answered = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Gap.m) {
                        Image(systemName: Self.headerSymbol)
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(Theme.Color.muted)
                            .accessibilityHidden(true)
                        Text(verbatim: Self.headline.text(in: locale))
                            .font(.title2.bold())
                            .foregroundStyle(Theme.Color.text)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("voiceConsent.headline")
                        Text(verbatim: Self.intro.text(in: locale))
                            .font(.body)
                            .foregroundStyle(Theme.Color.text)
                    }
                    .padding(.vertical, Theme.Gap.s)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Gap.xs, bottom: 0, trailing: Theme.Gap.xs))
                }
                Section {
                    ForEach(Self.points, id: \.symbol) { point in
                        ConsentPointRow(point: point, locale: locale)
                            .listRowBackground(Theme.Color.card)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            // No hyphenation: iOS 26.2 hyphenates Russian, measures a line without its hyphen and
            // then lays the text out narrower, so a paragraph lost its last line to an ellipsis.
            // English rules leave Cyrillic words whole.
            .typesettingLanguage(Locale.Language(identifier: "en"))
            .navigationTitle(Text(verbatim: Self.title.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        answer(false)
                    } label: {
                        Text(verbatim: Self.notNowTitle.text(in: locale))
                    }
                    .accessibilityIdentifier("voiceConsent.notNow")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: Self.agreeTitle.text(in: locale)) { answer(true) }
                        .accessibilityIdentifier("voiceConsent.agree")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
        // Pulled down without a word: the same as "Не сейчас".
        .onDisappear {
            if !answered { consent(false) }
        }
    }

    private func answer(_ agreed: Bool) {
        answered = true
        consent(agreed)
        dismiss()
    }

    // MARK: Content

    /// One thing the person agrees to: a symbol, a short title and the plain sentence under it.
    struct Point: Sendable {
        var symbol: String
        var title: LocalizedStringResource
        var text: LocalizedStringResource
    }

    static let headerSymbol = "waveform.badge.mic"

    static let points: [Point] = [
        Point(
            symbol: "waveform",
            title: LocalizedStringResource("What is sent", table: "Voice", comment: "Voice consent: title of the point that says what leaves the phone."),
            text: LocalizedStringResource(
                "Only the recording you make after tapping the mic, with the names and currencies of your accounts so Gemini can tell what you paid with. Balances and other records stay on the phone.",
                table: "Voice", comment: "Voice consent: exactly what is sent to Gemini."
            )
        ),
        Point(
            symbol: "key",
            title: LocalizedStringResource("Your own key", table: "Voice", comment: "Voice consent: title of the point about the API key."),
            text: LocalizedStringResource(
                "Requests go straight to Google with your Gemini API key. Golda has no servers of its own.",
                table: "Voice", comment: "Voice consent: whose key is used and where requests go."
            )
        ),
        Point(
            symbol: "globe",
            title: LocalizedStringResource("Google’s terms", table: "Voice", comment: "Voice consent: title of the point about how Google handles the recording."),
            text: LocalizedStringResource(
                "Google handles the recording under the Gemini API terms. On the phone it is deleted as soon as the operation is saved.",
                table: "Voice", comment: "Voice consent: who processes the recording and when it leaves the phone's storage."
            )
        ),
        Point(
            symbol: "hand.raised",
            title: LocalizedStringResource("Your choice", table: "Voice", comment: "Voice consent: title of the point about withdrawing consent."),
            text: LocalizedStringResource(
                "You can withdraw consent in Settings. Without it voice stays off, and “+” always works.",
                table: "Voice", comment: "Voice consent: how to take the consent back, and that manual entry works without it."
            )
        ),
    ]

    /// Short: the bar holds it between "Не сейчас" and "Согласен".
    static let title = LocalizedStringResource("Voice", table: "Voice", comment: "Title of the screen that asks before a recording is sent to the voice provider.")
    static let headline = LocalizedStringResource("Your voice goes to Google Gemini", table: "Voice", comment: "Voice consent: the headline naming the provider.")
    static let intro = LocalizedStringResource(
        "Golda does not recognise speech itself. To turn what you say into an operation, it sends the recording to Gemini, Google’s AI model.",
        table: "Voice", comment: "Voice consent: why the recording leaves the phone."
    )
    static let agreeTitle = LocalizedStringResource("Agree", table: "Voice", comment: "Voice consent: the button that gives consent.")
    static let notNowTitle = LocalizedStringResource("Not now", table: "Voice", comment: "Voice consent: the button that closes the screen without consent.")
}

private struct ConsentPointRow: View {
    let point: VoiceConsentScreen.Point
    let locale: Locale

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Gap.m) {
            GlyphCircle(point.symbol)
            VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                Text(verbatim: point.title.text(in: locale))
                    .font(.headline)
                    .foregroundStyle(Theme.Color.text)
                Text(verbatim: point.text.text(in: locale))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Color.muted)
            }
        }
        .padding(.vertical, Theme.Gap.xs)
        .accessibilityElement(children: .combine)
    }
}

/// The answer on the consent screen, handed to whoever asked: `RootView` passes the mic's, so
/// agreeing starts the recording the tap asked for. Elsewhere (previews) nobody listens.
struct VoiceConsentAction {
    let answer: @MainActor (Bool) -> Void

    @MainActor func callAsFunction(_ agreed: Bool) { answer(agreed) }
}

extension EnvironmentValues {
    @Entry var voiceConsent = VoiceConsentAction { _ in }
}

// MARK: - Previews

#Preview("Light") {
    Color.clear.sheet(isPresented: .constant(true)) { VoiceConsentScreen() }
}

#Preview("Dark") {
    Color.clear.sheet(isPresented: .constant(true)) { VoiceConsentScreen() }
        .preferredColorScheme(.dark)
}
