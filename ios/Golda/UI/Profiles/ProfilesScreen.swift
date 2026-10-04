import GoldaData
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.f4studio.golda", category: "Profiles")

/// The profiles of this phone as a sheet over the tabs, from the profile menu's "Управление
/// профилями": the list with "Готово", which closes it (every change is already kept).
struct ProfilesScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ProfilesList()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        ConfirmButton(title: Self.doneTitle.text(in: locale)) { dismiss() }
                            .accessibilityIdentifier("profiles.done")
                    }
                }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
    }

    static let doneTitle = LocalizedStringResource("Done", table: "Profiles", comment: "Closes the profiles screen, whose changes are already kept.")
}

/// A profile's own screen, pushed from its row.
struct ProfileRoute: Hashable {
    let profileId: UUID
}

/// The list of profiles: the active one ticked, a tap opens a profile's own screen, and each row
/// offers "Сделать активным", renaming and deleting (swipe and long press). "+ Новый профиль" asks
/// for a name and opens the new profile's screen to set it up; the active profile stays until it is
/// switched, here or from the menu.
///
/// It has no navigation stack of its own, so the settings can push it into theirs:
///
///     NavigationLink { ProfilesList() } label: { ... }
struct ProfilesList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var naming: ProfileNameRequest?
    /// The profile the name alert renames.
    @State private var renamingId: UUID?
    @State private var deletion: PendingDeletion?
    /// The profile just created, whose screen opens.
    @State private var created: ProfileRoute?
    @State private var failed = false

    private struct PendingDeletion {
        let profileId: UUID
        let deletion: ProfileDeletion
    }

    var body: some View {
        let rows = ProfileRow.rows(model.profiles, activeId: model.activeProfileId)
        let canDelete = ProfileDeletion.canDelete(profileCount: rows.count)
        List {
            Section {
                ForEach(rows) { row in
                    profileRow(row, canDelete: canDelete || model.sync.isParticipant(in: row.id))
                }
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Gap.s) {
                    Text(verbatim: Self.note.text(in: locale))
                    if !canDelete {
                        Text(verbatim: ProfileDeletion.lastProfileReason.text(in: locale))
                            .accessibilityIdentifier("profiles.lastProfileReason")
                    }
                }
            }
            Section {
                addRow
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        .animation(.snappy, value: rows)
        .navigationTitle(Text(verbatim: Self.title.text(in: locale)))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ProfileRoute.self) { route in
            ProfileScreen(profileId: route.profileId)
        }
        .navigationDestination(item: $created) { route in
            ProfileScreen(profileId: route.profileId)
        }
        .profileNameAlert($naming) { name in
            if let id = renamingId {
                rename(id, to: name)
            } else {
                create(name)
            }
        }
        .onChange(of: naming) { _, request in
            if request == nil { renamingId = nil }
        }
        .alert(
            Text(verbatim: deletion?.deletion.title(in: locale) ?? ""),
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            presenting: deletion
        ) { pending in
            Button(role: .destructive) {
                delete(pending.profileId, leaving: pending.deletion.sharing == .sharedWithMe)
            } label: {
                Text(verbatim: pending.deletion.confirmAction.text(in: locale))
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", tableName: "Profiles", comment: "Closes an alert or a sheet without changes.")
            }
        } message: { pending in
            Text(verbatim: pending.deletion.message(in: locale))
        }
        .alert(Text(verbatim: ProfileScreen.failureText.text(in: locale)), isPresented: $failed) {
            Button(role: .cancel) {} label: {
                Text("OK", tableName: "Profiles", comment: "Closes the message that a change was not saved.")
            }
        }
    }

    // MARK: Rows

    private func profileRow(_ row: ProfileRow, canDelete: Bool) -> some View {
        NavigationLink(value: ProfileRoute(profileId: row.id)) {
            HStack(spacing: Theme.Gap.m) {
                // At the accessibility sizes the name needs the room more than the glyph does.
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: ProfileSymbols.profile)
                        .font(.title3)
                        .foregroundStyle(Theme.Color.muted)
                        .accessibilityHidden(true)
                }
                Text(verbatim: row.name)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(2)
                Spacer(minLength: Theme.Gap.s)
                if row.isActive {
                    // Graphite: the active profile is what is picked (D34).
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Color.graphite)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Theme.minimumTarget)
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
        .accessibilityIdentifier("profiles.row")
        .swipeActions(edge: .leading) {
            if !row.isActive {
                Button {
                    model.switchProfile(to: row.id)
                } label: {
                    Label {
                        Text(verbatim: ProfileScreen.makeActiveTitle.text(in: locale))
                    } icon: {
                        Image(systemName: ProfileSymbols.makeActive)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            // The last profile has no delete to swipe to; the footer says why.
            if canDelete {
                Button(role: .destructive) {
                    askToDelete(row)
                } label: {
                    Label {
                        Text(verbatim: deleteTitle(row).text(in: locale))
                    } icon: {
                        Image(systemName: Symbols.delete)
                    }
                }
            }
            Button {
                askToRename(row)
            } label: {
                Label {
                    Text(verbatim: Self.renameTitle.text(in: locale))
                } icon: {
                    Image(systemName: ProfileSymbols.name)
                }
            }
        }
        .contextMenu {
            if !row.isActive {
                Button {
                    model.switchProfile(to: row.id)
                } label: {
                    Label {
                        Text(verbatim: ProfileScreen.makeActiveTitle.text(in: locale))
                    } icon: {
                        Image(systemName: ProfileSymbols.makeActive)
                    }
                }
            }
            Button {
                askToRename(row)
            } label: {
                Label {
                    Text(verbatim: Self.renameTitle.text(in: locale))
                } icon: {
                    Image(systemName: ProfileSymbols.name)
                }
            }
            Button(role: .destructive) {
                askToDelete(row)
            } label: {
                Label {
                    Text(verbatim: deleteTitle(row).text(in: locale))
                } icon: {
                    Image(systemName: Symbols.delete)
                }
            }
            .disabled(!canDelete)
        }
    }

    /// "+ Новый профиль" in the system blue, as an action row of an iOS list reads (D34).
    private var addRow: some View {
        Button {
            renamingId = nil
            naming = .create
        } label: {
            HStack(spacing: Theme.Gap.m) {
                Image(systemName: Symbols.add)
                Text(verbatim: ProfileNameRequest.create.title.text(in: locale))
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityIdentifier("profiles.add")
    }

    // MARK: Actions

    private func askToRename(_ row: ProfileRow) {
        renamingId = row.id
        naming = .rename(current: row.name)
    }

    /// "Удалить профиль", or "Выйти из профиля" for one someone shared with this person.
    private func deleteTitle(_ row: ProfileRow) -> LocalizedStringResource {
        model.sync.isParticipant(in: row.id) ? ProfileSharing.leaveTitle : ProfileDeletion.actionTitle
    }

    /// Counts what would go before asking; a failed count still asks, naming the kinds of things.
    /// A shared profile says who else loses it; someone else's profile is left, not deleted.
    private func askToDelete(_ row: ProfileRow) {
        let model = model
        Task {
            if model.sync.isParticipant(in: row.id) {
                deletion = PendingDeletion(profileId: row.id, deletion: ProfileDeletion(name: row.name, contents: nil, sharing: .sharedWithMe))
                return
            }
            var contents: ProfileContents?
            do {
                contents = try await model.profileContents(row.id)
            } catch {
                log.error("Counting a profile's contents failed: \(String(describing: error))")
            }
            let people = (try? await model.sync.participants(row.id)) ?? []
            let sharing = ProfileSharing(role: .owner, availability: model.sync.availability, participants: people).deletionKind
            deletion = PendingDeletion(profileId: row.id, deletion: ProfileDeletion(name: row.name, contents: contents, sharing: sharing))
        }
    }

    private func create(_ name: String) {
        let model = model
        Task {
            do {
                let profile = try await model.addProfile(name: name)
                created = ProfileRoute(profileId: profile.id)
            } catch {
                log.error("Creating a profile failed: \(String(describing: error))")
                failed = true
            }
        }
    }

    private func rename(_ id: UUID, to name: String) {
        let model = model
        Task {
            do {
                try await model.renameProfile(id, to: name)
            } catch {
                log.error("Renaming a profile failed: \(String(describing: error))")
                failed = true
            }
        }
    }

    private func delete(_ id: UUID, leaving: Bool) {
        let model = model
        Task {
            do {
                if leaving {
                    try await model.leaveProfile(id)
                } else {
                    try await model.deleteProfile(id)
                }
            } catch {
                log.error("Deleting a profile failed: \(String(describing: error))")
                failed = true
            }
        }
    }

    // MARK: Text

    static let title = LocalizedStringResource("Profiles", table: "Profiles", comment: "Title of the screen that lists, creates, renames and deletes profiles.")
    static let renameTitle = LocalizedStringResource("Rename", table: "Profiles", comment: "Profiles list: the action that renames a profile.")
    static let note = LocalizedStringResource(
        "Each profile keeps its own accounts, goals, payments and budget. The menu at the top of every tab switches between them.",
        table: "Profiles", comment: "Profiles list: what profiles are and where to switch them."
    )
}

#Preview("Samples") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) { ProfilesScreen() }
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Samples, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) { ProfilesScreen() }
        .environment(model)
        .environment(\.locale, Locale(identifier: "ru"))
        .preferredColorScheme(.dark)
        .task { await model.start(command: .samples) }
}
