import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Live Activity of a voice note recorded without opening the app (`VoiceActivityAttributes`):
/// «Слушаю…» with the seconds and «Стоп», then «Разбираю…», then what the note booked with
/// «Отменить», or why it needs the app. On the Lock Screen and in the Dynamic Island.
///
/// Colours as in the app: the system's ink and plain buttons; no accent, no red, since nothing here
/// is bad news. A tap anywhere else opens the app, where the toast or the form waits.
struct VoiceActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceActivityAttributes.self) { context in
            VoiceActivityLockScreen(state: context.state)
                .padding(16)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VoiceActivityGlyph(phase: state.phase)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.phase == .listening {
                        VoiceActivityClock(startedAt: state.startedAt)
                            .font(.title3.monospacedDigit())
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VoiceActivityBody(state: state)
                }
            } compactLeading: {
                VoiceActivityGlyph(phase: state.phase)
            } compactTrailing: {
                switch state.phase {
                case .listening:
                    VoiceActivityClock(startedAt: state.startedAt)
                        .monospacedDigit()
                        .frame(maxWidth: 40)
                case .thinking:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                default:
                    EmptyView()
                }
            } minimal: {
                VoiceActivityGlyph(phase: state.phase)
            }
        }
    }
}

/// The Lock Screen: the glyph beside what is going on and its button.
private struct VoiceActivityLockScreen: View {
    let state: VoiceActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VoiceActivityGlyph(phase: state.phase)
                .font(.title2)
                .frame(width: 32)
            VoiceActivityBody(state: state)
        }
    }
}

/// What the note is at, in words, with the button that belongs to it.
private struct VoiceActivityBody: View {
    let state: VoiceActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                switch state.phase {
                case .listening:
                    Text("Listening…", tableName: "VoiceActivity", comment: "Live Activity: the microphone is on for a voice note.")
                        .font(.headline)
                    VoiceActivityClock(startedAt: state.startedAt)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                case .thinking:
                    Text("Working it out…", tableName: "VoiceActivity", comment: "Live Activity: the voice note went to the model.")
                        .font(.headline)
                case .recorded:
                    Text(verbatim: state.headline)
                        .font(.headline)
                        .lineLimit(2)
                    if let detail = state.detail {
                        Text(verbatim: detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            // What is left for today, as the «Можно сегодня» widget hides it.
                            .privacySensitive()
                    } else {
                        Text("Saved", tableName: "VoiceActivity", comment: "Live Activity: the voice note was booked.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .undone:
                    Text("Undone", tableName: "VoiceActivity", comment: "Live Activity: what the voice note booked was deleted.")
                        .font(.headline)
                    if !state.headline.isEmpty {
                        Text(verbatim: state.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .lineLimit(1)
                    }
                case .needsApp:
                    Text(verbatim: state.headline)
                        .font(.subheadline)
                        .lineLimit(3)
                    Text("Open Golda", tableName: "VoiceActivity", comment: "Live Activity: a tap opens the app, where the voice note waits.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            button
        }
    }

    @ViewBuilder private var button: some View {
        switch state.phase {
        case .listening:
            Button(intent: StopVoiceNoteIntent()) {
                Label {
                    Text("Stop", tableName: "VoiceActivity", comment: "Live Activity button: ends the voice note.")
                } icon: {
                    Image(systemName: "stop.fill")
                }
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        case .recorded:
            if let ticket = state.undo {
                Button(intent: UndoVoiceNoteIntent(ticket)) {
                    Text("Undo", tableName: "VoiceActivity", comment: "Live Activity button: deletes what the voice note booked.")
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        default:
            EmptyView()
        }
    }
}

/// The seconds since the note started, counted by the system: the app does not wake to update it.
private struct VoiceActivityClock: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...startedAt.addingTimeInterval(60), countsDown: false)
    }
}

/// The mic while listening, then what became of the note.
private struct VoiceActivityGlyph: View {
    let phase: VoiceActivityAttributes.Phase

    var body: some View {
        switch phase {
        case .listening:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .accessibilityLabel(Text("Listening…", tableName: "VoiceActivity"))
        case .thinking:
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .accessibilityLabel(Text("Working it out…", tableName: "VoiceActivity"))
        case .recorded:
            Image(systemName: "checkmark")
                .accessibilityLabel(Text("Saved", tableName: "VoiceActivity"))
        case .undone:
            Image(systemName: "arrow.uturn.backward")
                .accessibilityLabel(Text("Undone", tableName: "VoiceActivity"))
        case .needsApp:
            Image(systemName: "arrow.up.forward.app")
                .accessibilityLabel(Text("Open Golda", tableName: "VoiceActivity"))
        }
    }
}

#Preview("Listening", as: .content, using: VoiceActivityAttributes()) {
    VoiceActivityWidget()
} contentStates: {
    VoiceActivityAttributes.ContentState(phase: .listening, startedAt: .now)
    VoiceActivityAttributes.ContentState(phase: .thinking, startedAt: .now)
    VoiceActivityAttributes.ContentState(
        phase: .recorded, startedAt: .now, headline: "Шаурма 15 ₾", detail: "≈ 0,4 ч работы · на сегодня осталось 503 ₽",
        undo: VoiceUndoTicket(profileId: UUID(), operationIds: [UUID()])
    )
}
