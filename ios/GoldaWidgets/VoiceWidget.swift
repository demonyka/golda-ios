import SwiftUI
import WidgetKit

/// Android's one-cell `VoiceWidget`: a mic that opens the app recording. The smallest Home Screen
/// widget, and the round one on the Lock Screen, the true one-cell size of iOS.
///
/// The whole widget is the link (`widgetURL`), as the whole Android cell was the button. A link
/// rather than `Button(intent:)`: a small widget's button covers only its glyph, and a tap beside
/// it would open the app without a note.
struct VoiceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.f4studio.golda.voice", provider: VoiceWidgetTimeline()) { _ in
            VoiceWidgetView()
        }
        .configurationDisplayName(Text("Say a purchase", tableName: "EntryPoints", comment: "The voice entry point: Shortcuts, Siri, Control Center, the quick action."))
        .description(Text("One tap and say what you spent", tableName: "EntryPoints", comment: "The voice widget in the widget gallery."))
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

/// Nothing changes on the widget, so one entry lasts for good.
struct VoiceWidgetTimeline: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

/// The plain mic glyph on the system's background: gold lives only in the app icon (D34), and the
/// glyph takes the tint of a tinted Home Screen like the system's own widgets. On the Lock Screen,
/// among other apps' circles, the app's coin in one colour says whose it is; a bare mic did not.
struct VoiceWidgetView: View {
    /// The coin as a custom symbol in the widgets' asset catalog, made by `tools/coin_symbol.py`.
    static let coinSymbol = "golda.coin"

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(VoiceEntry.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Say a purchase", tableName: "EntryPoints"))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(Self.coinSymbol)
                    .font(.system(size: 30))
                    .widgetAccentable()
            }
            .containerBackground(.clear, for: .widget)
        default:
            Image(systemName: "mic.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.primary)
                .widgetAccentable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(.background, for: .widget)
        }
    }
}

#Preview(as: .systemSmall) {
    VoiceWidget()
} timeline: {
    VoiceWidgetTimeline.Entry(date: .now)
}

#Preview(as: .accessoryCircular) {
    VoiceWidget()
} timeline: {
    VoiceWidgetTimeline.Entry(date: .now)
}
