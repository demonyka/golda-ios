#if DEBUG
import GoldaData
import GoldaSync
import SwiftUI
import UIKit

/// Settings → Sync, in debug builds only: iCloud's state, each profile's zone, what waits to be
/// sent or to be shown, and the transport's log to send back from a phone. English only, like
/// every debug screen; nothing of it ships. It reads the app's own sync, so it shows what the
/// books do (the 5a spike's separate file and zones are gone).
struct SyncDebugScreen: View {
    @Environment(AppModel.self) private var model
    @State private var queued: [OutgoingChange] = []
    @State private var waiting = 0
    @State private var device = ""

    var body: some View {
        let sync = model.sync
        List {
            Section {
                row("iCloud", "\(sync.availability)")
                row("Problem", sync.problem.map { "\($0)" } ?? "none")
                row("This install", device)
                row("Waiting to send", "\(queued.count) (\(queued.count(where: { $0.kind == .delete })) delete)")
                row("Waiting to show", "\(waiting)")
                Button { Task { await sync.syncNow(); await reload() } } label: { Text(verbatim: "Sync now") }
                    .accessibilityIdentifier("syncDebug.syncNow")
            } header: {
                Text(verbatim: "Sync")
            }

            Section {
                ForEach(model.profiles) { profile in
                    let zone = sync.zones[profile.id]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: profile.name)
                        Text(verbatim: "\(zone?.scope.rawValue ?? "-") · \(zone?.zoneName ?? "-")")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        if let zone, !zone.isOwned {
                            Text(verbatim: "owner \(zone.ownerName)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(verbatim: "Zones")
            }

            Section {
                Button { UIPasteboard.general.string = logText } label: { Text(verbatim: "Copy log") }
                ForEach(sync.logLines.reversed()) { entry in
                    Text(verbatim: "\(entry.date.formatted(date: .omitted, time: .standard)) [\(entry.scope?.rawValue ?? "-")] \(entry.message)")
                        .font(.caption2.monospaced())
                }
            } header: {
                Text(verbatim: "Log")
            }
        }
        .navigationTitle(Text(verbatim: "Sync"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await sync.syncNow(); await reload() }
        .task { await reload() }
    }

    private var logText: String {
        model.sync.logLines
            .map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.scope?.rawValue ?? "-")] \($0.message)" }
            .joined(separator: "\n")
    }

    private func reload() async {
        let store = model.sync.store
        queued = (try? await store.outgoing()) ?? []
        waiting = (try? await store.waitingCount()) ?? 0
        device = (try? await store.deviceName()) ?? ""
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
        } label: {
            Text(verbatim: title)
        }
    }
}
#endif
