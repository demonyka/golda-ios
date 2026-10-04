#if DEBUG
import CloudKit
import GoldaCore
import GoldaData
import GoldaSync
import Observation
import UIKit

/// Stage 5a's spike (ROADMAP): `CloudKitSyncTransport` on two phones with different Apple IDs,
/// driven by hand from Settings → Sync spike. Debug builds only.
///
/// It never touches the books: its profiles, operations and postings live in its own
/// `SyncStore` file (`Application Support/SyncSpike/sync.sqlite`) and in their own zones, and the
/// app's database is not opened here. Once started, it starts again with every launch, so
/// CloudKit's pushes find an engine to wake.
@MainActor
@Observable
final class SyncSpike {
    static let shared = SyncSpike()
    static let containerIdentifier = "iCloud.com.f4studio.golda"
    private static let enabledKey = "syncSpike.enabled"
    private static let deviceTagKey = "syncSpike.deviceTag"

    /// An operation of a spike zone with what has arrived of its postings.
    struct Entry: Identifiable {
        let operation: SyncRecord
        let note: String
        let postings: [SyncRecord]
        let postingCount: Int
        /// Who changed it last and when, as the server says.
        let serverAuthor: String?
        let serverDate: Date?

        var id: UUID { operation.payload.id }
        var isComplete: Bool { postings.count == postingCount }
        var amountMinor: Int64 {
            postings.reduce(0) { sum, record in
                if case .posting(let posting) = record.payload { return sum + posting.amountMinor }
                return sum
            }
        }
    }

    private(set) var isStarted = false
    private(set) var accountStatus = "not checked"
    private(set) var profiles: [SyncRecord] = []
    private(set) var entries: [SyncZone: [Entry]] = [:]
    private(set) var outgoing: [OutgoingChange] = []
    private(set) var shares: [SyncZone: String] = [:]
    private(set) var log: [SyncLogEntry] = []
    private(set) var lastDeleted: [SyncRecord] = []
    /// This phone in the records it writes: the model and a tag of three letters kept per install,
    /// so two phones of one model still differ.
    let device: String

    private var store: SyncStore?
    private(set) var transport: CloudKitSyncTransport?
    private var reloadTask: Task<Void, Never>?
    private var sharingDelegate: SharingDelegate?

    private init() {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let defaults = UserDefaults.standard
        let tag = defaults.string(forKey: Self.deviceTagKey) ?? {
            let letters = String((0..<3).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ".randomElement()! })
            defaults.set(letters, forKey: Self.deviceTagKey)
            return letters
        }()
        device = "\(machine) · \(tag)"
    }

    /// Starts the spike again at launch if it was ever started on this phone.
    func startIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        Task { await start() }
    }

    func start() async {
        guard !isStarted else { return }
        do {
            let store = try SyncStore.open(
                at: URL.applicationSupportDirectory.appending(path: "SyncSpike/sync.sqlite")
            )
            let transport = CloudKitSyncTransport(containerIdentifier: Self.containerIdentifier, store: store) { entry in
                Task { @MainActor in SyncSpike.shared.received(entry) }
            }
            self.store = store
            self.transport = transport
            isStarted = true
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            UIApplication.shared.registerForRemoteNotifications()
            try await transport.start()
            accountStatus = await transport.accountStatus().rawValue
            note("started as \(device)")
        } catch {
            note("start failed: \(error)")
        }
        await reload()
    }

    // MARK: Profiles

    /// A new profile of this person's, in its own zone; the books' profiles are not involved.
    func createProfile() async {
        await run("create profile") { store, transport in
            let id = UUID()
            let zone = SyncZone.own(id)
            try await transport.createZone(zone)
            let name = "Spike \(self.device.suffix(3)) \(Date().formatted(date: .omitted, time: .shortened))"
            try await store.save(self.record(zone, .profile(Profile(id: id, name: name))), now: self.now)
        }
    }

    func share(_ zone: SyncZone) async {
        guard let transport else { return }
        do {
            let title = profileName(zone)
            let share = try await transport.share(zone, title: title)
            note("share ready, \(share.participants.count) participant(s); presenting the sharing sheet")
            present(share, title: title)
        } catch {
            note("share failed: \(error)")
        }
        await refreshShare(zone)
    }

    func refreshShare(_ zone: SyncZone) async {
        guard let transport else { return }
        guard let share = await transport.existingShare(zone) else {
            shares[zone] = "not shared"
            return
        }
        let people = share.participants.map { participant in
            let name = participant.userIdentity.nameComponents?.formatted() ?? participant.userIdentity.lookupInfo?.emailAddress ?? "?"
            return "\(name) (\(Self.describe(participant.role)), \(Self.describe(participant.acceptanceStatus)), \(Self.describe(participant.permission)))"
        }
        shares[zone] = people.joined(separator: "\n")
    }

    func stopSharing(_ zone: SyncZone) async {
        await run("stop sharing") { _, transport in try await transport.stopSharing(zone) }
        await refreshShare(zone)
    }

    /// The owner deletes the profile for everyone; a participant leaves it.
    func remove(_ zone: SyncZone) async {
        await run(zone.isOwned ? "delete profile" : "leave share") { _, transport in try await transport.removeZone(zone) }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        await start()
        guard let transport else { return }
        do {
            try await transport.accept(metadata)
        } catch {
            note("accept failed: \(error)")
        }
        await reload()
    }

    // MARK: Records

    private static let titles = ["Кофе", "Хинкали", "Такси", "Продукты", "Аптека", "Кино", "Хлеб", "Метро"]

    /// An expense with its one posting: a header and a posting record, as the books will send them.
    func addRecord(_ zone: SyncZone) async {
        await run("add record") { store, _ in
            let id = UUID()
            let title = "\(Self.titles.randomElement()!) \(Date().formatted(date: .omitted, time: .standard))"
            let amount = Int64.random(in: 1...50) * 100
            let operation = GoldaCore.Operation(id: id, type: .expense, timestamp: self.now, note: title)
            // The spike has no accounts; the posting names the profile in their place.
            let posting = Posting(operationId: id, accountId: zone.profileId, amountMinor: -amount, rubMinor: -amount)
            try await store.save(self.record(zone, .operation(operation, postingCount: 1)), now: self.now)
            try await store.save(self.record(zone, .posting(posting)), now: self.now)
        }
    }

    /// Changes the note, so both phones editing one record offline make a conflict.
    func edit(_ entry: Entry) async {
        await run("edit record") { store, _ in
            guard case .operation(var operation, let count) = entry.operation.payload else { return }
            operation.note = "\(entry.note.split(separator: " ✎").first ?? "") ✎ \(self.device.suffix(3)) \(Date().formatted(date: .omitted, time: .standard))"
            try await store.save(self.record(entry.operation.zone, .operation(operation, postingCount: count)), now: self.now)
        }
    }

    /// Removes the operation and its postings here at once; the server hears of it after the undo
    /// window, unless "Undo delete" comes first.
    func delete(_ entry: Entry) async {
        await run("delete record") { store, _ in
            for record in [entry.operation] + entry.postings {
                try await store.delete(record.ref, now: self.now)
            }
        }
        lastDeleted = [entry.operation] + entry.postings
    }

    func undoDelete() async {
        let records = lastDeleted
        lastDeleted = []
        await run("undo delete") { store, _ in
            for record in records { try await store.save(record, now: self.now) }
        }
    }

    // MARK: Sync

    func fetchNow() async {
        await run("fetch now") { _, transport in try await transport.fetchNow() }
    }

    func sendNow() async {
        await run("send now") { _, transport in try await transport.sendNow() }
    }

    func checkAccount() async {
        guard let transport else { return }
        accountStatus = await transport.accountStatus().rawValue
    }

    func clearLog() {
        log = []
    }

    /// The whole log as text, to send back from the phone.
    var logText: String {
        log.map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.scope?.rawValue ?? "-")] \($0.message)" }
            .joined(separator: "\n")
    }

    // MARK: Reading

    func profileName(_ zone: SyncZone) -> String {
        for record in profiles where record.zone == zone {
            if case .profile(let profile) = record.payload { return profile.name }
        }
        return zone.zoneName
    }

    func reload() async {
        guard let store else { return }
        do {
            profiles = try await store.profiles()
            outgoing = try await store.outgoing()
            var entries: [SyncZone: [Entry]] = [:]
            for profile in profiles {
                entries[profile.zone] = try await Self.entries(in: profile.zone, store: store)
            }
            self.entries = entries
        } catch {
            note("reload failed: \(error)")
        }
    }

    private static func entries(in zone: SyncZone, store: SyncStore) async throws -> [Entry] {
        let records = try await store.records(in: zone)
        var postings: [UUID: [SyncRecord]] = [:]
        for record in records {
            if case .posting(let posting) = record.payload { postings[posting.operationId, default: []].append(record) }
        }
        var result: [Entry] = []
        for record in records {
            guard case .operation(let operation, let count) = record.payload else { continue }
            let server = try await store.systemFields(record.ref).flatMap(CloudKitMapping.record(fromSystemFields:))
            result.append(Entry(
                operation: record, note: operation.note, postings: postings[operation.id] ?? [], postingCount: count,
                serverAuthor: server?.lastModifiedUserRecordID?.recordName, serverDate: server?.modificationDate
            ))
        }
        return result.sorted { $0.operation.updatedAt > $1.operation.updatedAt }
    }

    // MARK: Helpers

    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func record(_ zone: SyncZone, _ payload: SyncPayload) -> SyncRecord {
        SyncRecord(zone: zone, payload: payload, updatedAt: now, authorDevice: device)
    }

    /// Runs [action], tells the transport the queue changed and shows the result; failures go to
    /// the log, which is what the owner sends back.
    private func run(_ name: String, _ action: @escaping (SyncStore, CloudKitSyncTransport) async throws -> Void) async {
        guard let store, let transport else {
            note("\(name): not started")
            return
        }
        do {
            try await action(store, transport)
            await transport.outgoingChanged()
        } catch {
            note("\(name) failed: \(error)")
        }
        await reload()
    }

    private func received(_ entry: SyncLogEntry) {
        log.append(entry)
        if log.count > 500 { log.removeFirst(log.count - 500) }
        // Events come in bursts; one reload after them is enough.
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func note(_ message: String) {
        received(SyncLogEntry(scope: nil, message: message))
    }

    // MARK: Sharing sheet

    /// `UICloudSharingController` over the existing share, presented from the top of the window:
    /// it offers Messages, Mail, AirDrop and copying the link, and lists the participants.
    private func present(_ share: CKShare, title: String) {
        guard let transport,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController
        else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UICloudSharingController(share: share, container: transport.container)
        let delegate = SharingDelegate(title: title) { [weak self] message in
            self?.note(message)
            Task { await self?.reload() }
        }
        sharingDelegate = delegate
        controller.delegate = delegate
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        top.present(controller, animated: true)
    }

    private final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let report: @MainActor (String) -> Void

        init(title: String, report: @escaping @MainActor (String) -> Void) {
            self.title = title
            self.report = report
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            report("sharing sheet: failed to save the share: \(error)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            report("sharing sheet: share saved")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            report("sharing sheet: sharing stopped")
        }
    }

    private static func describe(_ role: CKShare.ParticipantRole) -> String {
        switch role {
        case .owner: "owner"
        case .privateUser: "invited"
        case .publicUser: "public"
        case .administrator: "admin"
        default: "unknown"
        }
    }

    private static func describe(_ status: CKShare.ParticipantAcceptanceStatus) -> String {
        switch status {
        case .pending: "pending"
        case .accepted: "accepted"
        case .removed: "removed"
        default: "unknown"
        }
    }

    private static func describe(_ permission: CKShare.ParticipantPermission) -> String {
        switch permission {
        case .readOnly: "read only"
        case .readWrite: "read and write"
        case .none: "none"
        default: "unknown"
        }
    }
}
#endif
