#if DEBUG
import GoldaSync
import SwiftUI

/// Settings → Sync spike, in debug builds only: iCloud's state, the spike's profiles and zones,
/// and the log the owner sends back. English only, like every debug screen; nothing of it ships.
struct SyncSpikeScreen: View {
    @State private var spike = SyncSpike.shared

    var body: some View {
        List {
            Section {
                row("iCloud account", spike.accountStatus)
                row("Container", SyncSpike.containerIdentifier)
                row("This phone", spike.device)
                row("Waiting to send", outgoingSummary)
                Button { Task { await spike.fetchNow() } } label: { Text(verbatim: "Fetch now") }
                    .accessibilityIdentifier("syncSpike.fetch")
                Button { Task { await spike.sendNow() } } label: { Text(verbatim: "Send now") }
                    .accessibilityIdentifier("syncSpike.send")
                Button { Task { await spike.checkAccount() } } label: { Text(verbatim: "Check account") }
            } header: {
                Text(verbatim: "iCloud")
            }

            Section {
                ForEach(spike.profiles, id: \.zone) { profile in
                    NavigationLink {
                        SyncSpikeProfileScreen(zone: profile.zone)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: spike.profileName(profile.zone))
                            Text(verbatim: "\(profile.zone.scope.rawValue) · \(profile.zone.zoneName)")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            if !profile.zone.isOwned {
                                Text(verbatim: "owner \(profile.zone.ownerName)")
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Text(verbatim: "\(spike.entries[profile.zone]?.count ?? 0) record(s)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button { Task { await spike.createProfile() } } label: { Text(verbatim: "New spike profile") }
                    .accessibilityIdentifier("syncSpike.newProfile")
            } header: {
                Text(verbatim: "Spike profiles (one zone each)")
            } footer: {
                Text(verbatim: "The spike keeps its own profiles in its own file and zones; the books are not touched.")
            }

            SyncSpikeLogSection()
        }
        .navigationTitle(Text(verbatim: "Sync spike"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await spike.fetchNow() }
        .task { await spike.start() }
    }

    private var outgoingSummary: String {
        let waiting = spike.outgoing.filter { $0.handedRevision != $0.revision }.count
        return "\(spike.outgoing.count) (\(waiting) not yet handed to CloudKit)"
    }
}

/// One spike profile: its share, its records and what can be done to them.
struct SyncSpikeProfileScreen: View {
    let zone: SyncZone
    @State private var spike = SyncSpike.shared
    @State private var confirmsRemoval = false

    var body: some View {
        List {
            Section {
                row("Zone", zone.zoneName)
                row("Database", zone.scope.rawValue)
                row("Owner", zone.isOwned ? "this person" : zone.ownerName)
                row("Share", spike.shares[zone] ?? "…")
                if zone.isOwned {
                    Button { Task { await spike.share(zone) } } label: { Text(verbatim: "Share…") }
                        .accessibilityIdentifier("syncSpike.share")
                    Button { Task { await spike.stopSharing(zone) } } label: { Text(verbatim: "Stop sharing") }
                        .accessibilityIdentifier("syncSpike.stopSharing")
                }
                Button { confirmsRemoval = true } label: {
                    Text(verbatim: zone.isOwned ? "Delete profile for everyone" : "Leave share")
                }
                .accessibilityIdentifier("syncSpike.remove")
            } header: {
                Text(verbatim: spike.profileName(zone))
            }

            Section {
                Button { Task { await spike.addRecord(zone) } } label: { Text(verbatim: "Add record") }
                    .accessibilityIdentifier("syncSpike.add")
                if !spike.lastDeleted.isEmpty {
                    Button { Task { await spike.undoDelete() } } label: { Text(verbatim: "Undo delete (within 10 s)") }
                }
                ForEach(spike.entries[zone] ?? []) { entry in
                    entryRow(entry)
                        .swipeActions {
                            Button(role: .destructive) { Task { await spike.delete(entry) } } label: { Text(verbatim: "Delete") }
                            Button { Task { await spike.edit(entry) } } label: { Text(verbatim: "Edit") }
                        }
                }
            } header: {
                Text(verbatim: "Records (swipe for Edit and Delete)")
            }

            Section {
                Button { Task { await spike.fetchNow() } } label: { Text(verbatim: "Fetch now") }
                Button { Task { await spike.sendNow() } } label: { Text(verbatim: "Send now") }
            }

            SyncSpikeLogSection()
        }
        .navigationTitle(Text(verbatim: spike.profileName(zone)))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await spike.fetchNow() }
        .task { await spike.refreshShare(zone) }
        .confirmationDialog(
            Text(verbatim: zone.isOwned ? "Delete the zone on the server?" : "Leave the share?"),
            isPresented: $confirmsRemoval
        ) {
            Button(role: .destructive) { Task { await spike.remove(zone) } } label: {
                Text(verbatim: zone.isOwned ? "Delete for everyone" : "Leave")
            }
        }
    }

    private func entryRow(_ entry: SyncSpike.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: entry.note)
                Spacer()
                Text(verbatim: entry.isComplete ? Self.money(entry.amountMinor) : "postings \(entry.postings.count)/\(entry.postingCount)")
                    .monospacedDigit()
            }
            Text(verbatim: "by \(entry.operation.authorDevice) at \(Date(timeIntervalSince1970: Double(entry.operation.updatedAt) / 1000).formatted(date: .omitted, time: .standard))")
                .font(.caption).foregroundStyle(.secondary)
            Text(verbatim: "server: \(entry.serverAuthor ?? "not on the server yet")\(entry.serverDate.map { " at \($0.formatted(date: .omitted, time: .standard))" } ?? "")")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private static func money(_ minor: Int64) -> String {
        String(format: "%.2f", Double(minor) / 100)
    }
}

/// The engines' events, newest last, with a button to copy them all for the report.
private struct SyncSpikeLogSection: View {
    @State private var spike = SyncSpike.shared

    var body: some View {
        Section {
            Button { UIPasteboard.general.string = spike.logText } label: { Text(verbatim: "Copy log") }
                .accessibilityIdentifier("syncSpike.copyLog")
            Button { spike.clearLog() } label: { Text(verbatim: "Clear log") }
            ForEach(spike.log.suffix(150).reversed()) { entry in
                Text(verbatim: "\(entry.date.formatted(date: .omitted, time: .standard)) [\(entry.scope?.rawValue ?? "-")] \(entry.message)")
                    .font(.caption2.monospaced())
            }
        } header: {
            Text(verbatim: "Log (newest first)")
        }
    }
}

private func row(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(verbatim: title)
        Spacer()
        Text(verbatim: value)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
    }
}
#endif
