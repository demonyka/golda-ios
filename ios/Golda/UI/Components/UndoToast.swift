import SwiftUI

// MARK: - Model and timing

/// A message with one action, shown for a few seconds above the tab bar: the Android snackbar.
/// "Coffee −8 ₾ · Undo", "“Rent” deleted · Undo".
struct UndoToast: Identifiable, Equatable {
    /// How long it stays, the two lengths of the Android snackbar.
    enum Length: Sendable {
        /// 4 s: a small confirmation.
        case short
        /// 10 s: a message with several lines, or one that undoes something that is hard to redo.
        case long
    }

    let id = UUID()
    /// May run to several lines ("Coffee −8 ₾\nOver the daily budget").
    var message: String
    var actionTitle: String
    var length: Length
    /// Runs when the action is tapped, on the main actor.
    var action: @MainActor () -> Void

    init(
        _ message: String,
        actionTitle: String = String(localized: "Undo", table: "Components"),
        length: Length = .short,
        action: @escaping @MainActor () -> Void
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.length = length
        self.action = action
    }

    static func == (lhs: UndoToast, rhs: UndoToast) -> Bool { lhs.id == rhs.id }
}

/// How long a toast stays, and the wait itself, on a clock the caller chooses so a test can drive it.
enum UndoToastTiming {
    static func duration(_ length: UndoToast.Length) -> Duration {
        switch length {
        case .short: .seconds(4)
        case .long: .seconds(10)
        }
    }

    /// With VoiceOver on, even a short toast stays as long as a long one: reading the message and
    /// finding the action takes longer than 4 s.
    static func visibleDuration(_ length: UndoToast.Length, voiceOverRunning: Bool) -> Duration {
        voiceOverRunning ? max(duration(length), duration(.long)) : duration(length)
    }

    /// Waits `duration` on `clock`. True when the time ran out (hide the toast), false when the wait
    /// was cancelled first (the toast was dismissed, replaced or left the screen).
    static func runOut<C: Clock>(after duration: C.Duration, on clock: C) async -> Bool {
        do {
            try await clock.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - View

/// The capsule itself: the message, and the action as a button of at least 44 pt in the system
/// blue, so it reads as something to tap (D34). Dark ink on a light fill in the dark theme and the
/// other way round in the light one: it stands out from the cards it floats over, the way the
/// Android snackbar does.
struct UndoToastView: View {
    var toast: UndoToast
    var onAction: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Gap.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Gap.m))
        layout {
            Text(toast.message)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Gap.s)
            Button(action: onAction) {
                Text(toast.actionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(minWidth: Theme.minimumTarget, minHeight: Theme.minimumTarget, alignment: .center)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The fill is the other theme's, so the blue is too: the brighter dark-theme blue on
            // the dark capsule, the deeper light-theme one on the light capsule.
            .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
        }
        // More room at the rounded ends than at the action, which is a tap target in its own right.
        .padding(.leading, Theme.Gap.l - Theme.Gap.xs)
        .padding(.trailing, Theme.Gap.s)
        .foregroundStyle(Theme.Color.page)
        .background(Theme.Color.text, in: RoundedRectangle(cornerRadius: Theme.Radius.toast, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }
}

/// Shows the toast bound to `toast` above the bottom bar and hides it after its time.
///
/// Apply it to a screen *inside* the `TabView`, and on a tab's screen inside the mic's inset: the
/// tab bar and the mic are then part of that view's safe area, and the toast floats above both.
/// Setting the binding to a new toast replaces the one on screen and restarts the time.
private struct UndoToastHost: ViewModifier {
    @Binding var toast: UndoToast?

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    UndoToastView(toast: toast) { perform(toast) }
                        .padding(.horizontal, Theme.Gap.m)
                        .padding(.bottom, Theme.Gap.s)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .gesture(
                            DragGesture(minimumDistance: 12).onEnded { drag in
                                if drag.translation.height > 16 { dismiss(toast) }
                            }
                        )
                        .id(toast.id)
                        .task(id: toast.id) {
                            AccessibilityNotification.Announcement(toast.message).post()
                            let time = UndoToastTiming.visibleDuration(toast.length, voiceOverRunning: voiceOverRunning)
                            if await UndoToastTiming.runOut(after: time, on: ContinuousClock()) { dismiss(toast) }
                        }
                }
            }
            .animation(.snappy, value: toast?.id)
    }

    private func perform(_ shown: UndoToast) {
        shown.action()
        dismiss(shown)
    }

    /// Only hides the toast that asked: a replacement that arrived meanwhile stays.
    private func dismiss(_ shown: UndoToast) {
        if toast?.id == shown.id { toast = nil }
    }
}

extension View {
    /// Shows `toast` as a capsule above the tab bar until its time runs out or its action is tapped.
    func undoToast(_ toast: Binding<UndoToast?>) -> some View {
        modifier(UndoToastHost(toast: toast))
    }
}

// MARK: - Previews

private struct UndoToastGallery: View {
    var body: some View {
        VStack(spacing: Theme.Gap.m) {
            UndoToastView(toast: UndoToast("Coffee −8 ₾") {}, onAction: {})
            UndoToastView(
                toast: UndoToast("Shawarma −15 ₾ · Coffee −8 ₾\nThat is 23 ₾ of today's 52 ₾", actionTitle: "Undo", length: .long) {},
                onAction: {}
            )
            UndoToastView(toast: UndoToast("“Rent” deleted", actionTitle: "Restore") {}, onAction: {})
        }
        .padding(Theme.Gap.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.page)
    }
}

#Preview("Light") { UndoToastGallery() }
#Preview("Dark") { UndoToastGallery().preferredColorScheme(.dark) }
#Preview("Accessibility XXL") { UndoToastGallery().dynamicTypeSize(.accessibility3) }

/// The host at work: tap to show a toast, which hides itself after four seconds.
#Preview("Host") {
    @Previewable @State var toast: UndoToast?
    TabView {
        Tab(String("Home"), systemImage: "house") {
            ZStack {
                Theme.Color.page.ignoresSafeArea()
                Button(String("Show toast")) {
                    toast = UndoToast("Coffee −8 ₾ saved\nFrom a saved note") { toast = nil }
                }
            }
            .undoToast($toast)
        }
        Tab(String("Accounts"), systemImage: "wallet.pass") { Theme.Color.page.ignoresSafeArea() }
    }
}
