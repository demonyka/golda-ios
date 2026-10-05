import GoldaCore
import GoldaData
import GoldaSync
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.f4studio.golda", category: "Profiles")

/// One profile's own screen: its name and whether it is the active one, the income (rate, tax and
/// hours, payday, an hour after tax), the markup over the CBR, the monthly payments, who it is
/// shared with, and deleting it (or leaving it, when it is someone else's). What Android kept in
/// its settings and belongs to a profile here (D21).
///
/// It follows the profile's books itself, so any profile can be set up, the active one or not; a
/// change to the active one shows on Home at once. When the profile goes (deleted here or
/// elsewhere), the screen closes.
struct ProfileScreen: View {
    let profileId: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var snapshot: ProfileSnapshot?
    @State private var editing: Edit?
    @State private var paymentForm: PaymentFormRequest?
    @State private var naming: ProfileNameRequest?
    @State private var deletion: ProfileDeletion?
    @State private var toast: UndoToast?
    @State private var failed = false
    /// Who the profile is shared with, as iCloud last said.
    @State private var participants: [SyncParticipant] = []
    @State private var askingToStopSharing = false
    /// Why a sharing action failed, in words.
    @State private var sharingFailure: String?

    /// The small sheet open over the screen.
    private enum Edit: String, Identifiable {
        case rate, taxHours, payday, markup
        var id: String { rawValue }
    }

    /// The payment form: empty from "+ Платёж", or for a payment from its row.
    private struct PaymentFormRequest: Identifiable {
        let obligation: Obligation?
        let id = UUID()
    }

    var body: some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Color.page)
            }
        }
        .navigationTitle(Text(verbatim: snapshot?.profile.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: profileId) { await follow() }
        .sheet(item: $editing) { edit in
            if let settings = snapshot?.profile.settings { sheet(edit, settings: settings) }
        }
        .sheet(item: $paymentForm) { request in
            if let snapshot {
                ObligationSheet(
                    editing: request.obligation,
                    settings: Settings(profile: snapshot.profile.settings, device: model.device, profileId: profileId),
                    onSave: save, onDelete: delete
                )
            }
        }
        .profileNameAlert($naming) { name in rename(to: name) }
        .alert(
            Text(verbatim: deletion?.title(in: locale) ?? ""),
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            presenting: deletion
        ) { deletion in
            Button(role: .destructive) {
                deleteProfile(leaving: deletion.sharing == .sharedWithMe)
            } label: {
                Text(verbatim: deletion.confirmAction.text(in: locale))
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", tableName: "Profiles", comment: "Closes an alert or a sheet without changes.")
            }
        } message: { deletion in
            Text(verbatim: deletion.message(in: locale))
        }
        .alert(Text(verbatim: Self.failureText.text(in: locale)), isPresented: $failed) {
            Button(role: .cancel) {} label: {
                Text("OK", tableName: "Profiles", comment: "Closes the message that a change was not saved.")
            }
        }
        .alert(
            Text(verbatim: ProfileSharing.stopQuestion(snapshot?.profile.name ?? "", in: locale)),
            isPresented: $askingToStopSharing
        ) {
            Button(role: .destructive, action: stopSharing) {
                Text(verbatim: ProfileSharing.stopTitle.text(in: locale))
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", tableName: "Profiles", comment: "Closes an alert or a sheet without changes.")
            }
        } message: {
            Text(verbatim: ProfileSharing.stopQuestionMessage.text(in: locale))
        }
        .alert(
            Text(verbatim: sharingFailure ?? ""),
            isPresented: Binding(get: { sharingFailure != nil }, set: { if !$0 { sharingFailure = nil } })
        ) {
            Button(role: .cancel) {} label: {
                Text("OK", tableName: "Profiles", comment: "Closes the message that a change was not saved.")
            }
        }
        .task(id: model.sync.zones[profileId]) { await loadParticipants() }
        .undoToast($toast)
    }

    /// What this person may do about sharing the profile, now.
    private var sharing: ProfileSharing {
        ProfileSharing(
            role: model.sync.isParticipant(in: profileId) ? .participant : .owner,
            availability: model.sync.availability, participants: participants, problem: model.sync.problem
        )
    }

    // MARK: Content

    private func content(_ snapshot: ProfileSnapshot) -> some View {
        let profile = snapshot.profile
        let income = ProfileIncome(profile.settings, today: model.environment.today())
        let isActive = model.activeProfileId == profile.id
        let canDelete = ProfileDeletion.canDelete(profileCount: model.profiles.count)
        return List {
            Section {
                valueRow(
                    title: Self.nameTitle, value: profile.name, symbol: ProfileSymbols.name, identifier: "profile.name"
                ) { naming = .rename(current: profile.name) }
                activeRow(isActive: isActive)
            } footer: {
                Text(verbatim: Self.activeNote.text(in: locale))
            }

            Section {
                valueRow(title: income.rateTitle, value: income.rateText(in: locale), symbol: ProfileSymbols.rate, identifier: "profile.rate") {
                    editing = .rate
                }
                valueRow(
                    title: ProfileIncome.taxHoursTitle, value: income.taxHoursText(in: locale), symbol: ProfileSymbols.taxHours,
                    identifier: "profile.taxHours"
                ) { editing = .taxHours }
                valueRow(
                    title: ProfileIncome.paydayTitle, value: income.paydayText(in: locale), symbol: ProfileSymbols.payday,
                    identifier: "profile.payday"
                ) { editing = .payday }
                hourNetRow(income)
            } header: {
                Text(verbatim: ProfileIncome.title.text(in: locale))
            }

            Section {
                valueRow(
                    title: MarkupForm.title, value: ProfileIncome.markupText(profile.settings.markup), symbol: ProfileSymbols.markup,
                    identifier: "profile.markup"
                ) { editing = .markup }
            } header: {
                Text(verbatim: Self.exchangeTitle.text(in: locale))
            } footer: {
                Text(verbatim: MarkupForm.note.text(in: locale))
            }

            Section {
                ForEach(snapshot.obligations.map(ObligationRow.init)) { row in
                    paymentRow(row)
                }
                addPaymentRow
            } header: {
                Text(verbatim: Self.paymentsTitle.text(in: locale))
            } footer: {
                Text(verbatim: Self.paymentsNote.text(in: locale))
            }

            sharingSection(profile, sharing: sharing)

            Section {
                if sharing.canLeave {
                    // Leaving takes the profile from this phone, which is bad news: red, as a delete.
                    Button(role: .destructive) {
                        deletion = ProfileDeletion(name: profile.name, contents: nil, sharing: .sharedWithMe)
                    } label: {
                        ActionRowLabel(
                            title: ProfileSharing.leaveTitle.text(in: locale), symbol: ProfileSymbols.leave,
                            ink: AnyShapeStyle(Theme.Color.danger)
                        )
                    }
                    .accessibilityIdentifier("profile.leave")
                } else {
                    Button(role: .destructive) {
                        deletion = ProfileDeletion(name: profile.name, contents: ProfileContents(snapshot), sharing: sharing.deletionKind)
                    } label: {
                        // Red only while it can delete; the last profile's row reads as unavailable.
                        ActionRowLabel(
                            title: ProfileDeletion.actionTitle.text(in: locale), symbol: Symbols.delete,
                            ink: AnyShapeStyle(canDelete ? Theme.Color.danger : Theme.Color.muted)
                        )
                    }
                    .disabled(!canDelete)
                    .accessibilityIdentifier("profile.delete")
                }
            } footer: {
                if !canDelete, !sharing.canLeave {
                    Text(verbatim: ProfileDeletion.lastProfileReason.text(in: locale))
                        .accessibilityIdentifier("profile.lastProfileReason")
                }
            }
        }
        .refreshable {
            await model.sync.syncNow()
            await loadParticipants()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        .animation(.snappy, value: snapshot.obligations)
    }

    /// Who the profile is shared with, "Пригласить…" (the system share sheet: AirDrop, Messages,
    /// Mail, Copy Link) and "Закрыть доступ" for the owner; without iCloud, a word on why not.
    private func sharingSection(_ profile: Profile, sharing: ProfileSharing) -> some View {
        Section {
            ForEach(sharing.people) { person in
                personRow(person)
            }
            if sharing.role == .owner {
                if sharing.canInvite, let invitation = model.sync.invitation(for: profile.id, title: profile.name) {
                    ShareLink(
                        item: invitation,
                        preview: SharePreview(Text(verbatim: profile.name), image: Image(systemName: ProfileSymbols.profile))
                    ) {
                        // An action row in the system blue, as an iOS list writes one (D34).
                        ActionRowLabel(
                            title: ProfileSharing.inviteTitle.text(in: locale), symbol: ProfileSymbols.invite, ink: AnyShapeStyle(.tint)
                        )
                    }
                    .listRowBackground(Theme.Color.card)
                    .accessibilityIdentifier("profile.invite")
                } else {
                    Button {} label: {
                        ActionRowLabel(
                            title: ProfileSharing.inviteTitle.text(in: locale), symbol: ProfileSymbols.invite,
                            ink: AnyShapeStyle(Theme.Color.muted)
                        )
                    }
                    .disabled(true)
                    .listRowBackground(Theme.Color.card)
                    .accessibilityIdentifier("profile.invite")
                }
            }
            if sharing.canStopSharing {
                Button(role: .destructive) {
                    askingToStopSharing = true
                } label: {
                    ActionRowLabel(
                        title: ProfileSharing.stopTitle.text(in: locale), symbol: ProfileSymbols.stopSharing,
                        ink: AnyShapeStyle(Theme.Color.danger)
                    )
                }
                .listRowBackground(Theme.Color.card)
                .accessibilityIdentifier("profile.stopSharing")
            }
        } header: {
            Text(verbatim: ProfileSharing.title.text(in: locale))
        } footer: {
            Text(verbatim: sharing.note(in: locale))
                .accessibilityIdentifier("profile.sharingNote")
        }
    }

    /// A person in the profile: their name, and what they are when not a plain member.
    private func personRow(_ person: SyncParticipant) -> some View {
        HStack(spacing: Theme.Gap.m) {
            Image(systemName: ProfileSymbols.person)
                .foregroundStyle(Theme.Color.muted)
                .frame(width: ProfileSymbols.width)
                .accessibilityHidden(true)
            Text(verbatim: ProfileSharing.name(of: person, in: locale))
                .foregroundStyle(Theme.Color.text)
                .lineLimit(2)
            Spacer(minLength: Theme.Gap.s)
            if let detail = ProfileSharing.detail(of: person, in: locale) {
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Color.muted)
                    .multilineTextAlignment(.trailing)
            }
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.person")
    }

    /// A setting: its glyph and name, and its value at the end in quiet ink. A tap opens its sheet.
    private func valueRow(
        title: LocalizedStringResource, value: String, symbol: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            LabeledContent {
                Text(verbatim: value)
                    .tabularDigits()
                    .foregroundStyle(Theme.Color.muted)
                    .multilineTextAlignment(.trailing)
            } label: {
                RowLabel(title: title.text(in: locale), symbol: symbol)
            }
            .contentShape(.rect)
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func activeRow(isActive: Bool) -> some View {
        if isActive {
            HStack(spacing: Theme.Gap.m) {
                Image(systemName: ProfileSymbols.active)
                    .foregroundStyle(Theme.Color.graphite)
                    .frame(width: ProfileSymbols.width)
                    .accessibilityHidden(true)
                Text(verbatim: Self.activeTitle.text(in: locale))
                    .foregroundStyle(Theme.Color.text)
            }
            .listRowBackground(Theme.Color.card)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.active")
        } else {
            // An action row in the system blue, as an iOS list writes one (D34).
            Button {
                model.switchProfile(to: profileId)
            } label: {
                ActionRowLabel(title: Self.makeActiveTitle.text(in: locale), symbol: ProfileSymbols.makeActive, ink: AnyShapeStyle(.tint))
            }
            .listRowBackground(Theme.Color.card)
            .accessibilityIdentifier("profile.makeActive")
        }
    }

    /// "Час на руки" with last month's pay under it, and the hour itself as the row's number.
    /// At the accessibility sizes the hour goes under the title, so neither is cut.
    private func hourNetRow(_ income: ProfileIncome) -> some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let hourNet = Text(verbatim: income.hourNet)
            .font(.title3.weight(.semibold))
            .tabularDigits()
            .foregroundStyle(Theme.Color.text)
            .lineLimit(1)
            .accessibilityIdentifier("profile.hourNet")
        return HStack(alignment: .center, spacing: Theme.Gap.m) {
            Color.clear
                .frame(width: ProfileSymbols.width, height: 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                Text(verbatim: ProfileIncome.hourNetTitle.text(in: locale))
                    .foregroundStyle(Theme.Color.text)
                if isLarge { hourNet }
                Text(verbatim: income.lastMonthText(in: locale).keepingMarksOnTheLine)
                    .font(.subheadline)
                    .tabularDigits()
                    .foregroundStyle(Theme.Color.muted)
            }
            Spacer(minLength: Theme.Gap.s)
            if !isLarge { hourNet }
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityElement(children: .combine)
    }

    private func paymentRow(_ row: ObligationRow) -> some View {
        Button {
            paymentForm = PaymentFormRequest(obligation: row.obligation)
        } label: {
            // At the accessibility sizes the glyph gives its room to the name, and the amount goes
            // under it, so neither is cut.
            let isLarge = dynamicTypeSize.isAccessibilitySize
            let amount = Text(verbatim: row.amount)
                .tabularDigits()
                .foregroundStyle(Theme.Color.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: Theme.Gap.m) {
                if !isLarge {
                    Image(systemName: ProfileSymbols.payment)
                        .foregroundStyle(Theme.Color.muted)
                        .frame(width: ProfileSymbols.width)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.name)
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(isLarge ? nil : 2)
                    if isLarge { amount }
                    Text(verbatim: row.dayText(in: locale))
                        .font(.subheadline)
                        .foregroundStyle(Theme.Color.muted)
                }
                Spacer(minLength: Theme.Gap.s)
                if !isLarge { amount }
            }
            .contentShape(.rect)
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
        .accessibilityIdentifier("profile.payment")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(row.obligation)
            } label: {
                Label {
                    Text(verbatim: ObligationForm.deleteTitle.text(in: locale))
                } icon: {
                    Image(systemName: Symbols.delete)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                delete(row.obligation)
            } label: {
                Label {
                    Text(verbatim: ObligationForm.deleteTitle.text(in: locale))
                } icon: {
                    Image(systemName: Symbols.delete)
                }
            }
        }
    }

    /// "+ Платёж" in the system blue, as an action row of an iOS list reads (D34).
    private var addPaymentRow: some View {
        Button {
            paymentForm = PaymentFormRequest(obligation: nil)
        } label: {
            HStack(spacing: Theme.Gap.m) {
                Image(systemName: Symbols.add)
                    .frame(width: ProfileSymbols.width)
                Text(verbatim: Self.addPaymentTitle.text(in: locale))
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityLabel(Text(verbatim: Self.addPaymentLabel.text(in: locale)))
        .accessibilityIdentifier("profile.addPayment")
    }

    @ViewBuilder private func sheet(_ edit: Edit, settings: ProfileSettings) -> some View {
        switch edit {
        case .rate: RateSheet(settings: settings, onSave: update)
        case .taxHours: TaxHoursSheet(settings: settings, onSave: update)
        case .payday: PaydaySheet(payday: settings.payday, onSave: update)
        case .markup: MarkupSheet(markup: settings.markup, onSave: update)
        }
    }

    // MARK: Actions

    /// Follows the profile's books until the profile is gone; then its screen closes. Books that
    /// cannot be read put the app's failure screen up rather than a spinner that never ends.
    private func follow() async {
        do {
            for try await snapshot in model.profileSnapshots(profileId) {
                self.snapshot = snapshot
            }
        } catch {
            if !Task.isCancelled { model.fail(error) }
            return
        }
        // Leaving the screen ends the loop too; only a deleted profile closes it.
        if !Task.isCancelled { dismiss() }
    }

    /// Applies [change] to the profile's settings as they are now: a markup learned from an
    /// exchange while a sheet was open is kept.
    private func update(_ change: @escaping ProfileSettingsChange) {
        guard let current = snapshot?.profile.settings, let settings = change(current), settings != current else { return }
        let model = model, profileId = profileId
        Task {
            do {
                try await model.saveProfileSettings(settings, profileId: profileId)
            } catch {
                log.error("Saving the profile's settings failed: \(String(describing: error))")
                failed = true
            }
        }
    }

    private func rename(to name: String) {
        let model = model, profileId = profileId
        Task {
            do {
                try await model.renameProfile(profileId, to: name)
            } catch {
                log.error("Renaming a profile failed: \(String(describing: error))")
                failed = true
            }
        }
    }

    private func save(_ obligation: Obligation) {
        let model = model, profileId = profileId
        Task {
            do {
                try await model.saveObligation(obligation, profileId: profileId)
            } catch {
                log.error("Saving a payment failed: \(String(describing: error))")
                failed = true
            }
        }
    }

    /// Deletes the payment at once and offers "Отменить", which puts it back with the same id. The
    /// toast stays 10 s, as Android's does for a payment, a goal or an operation: a deletion is
    /// worth more than the 4 s of a confirmation.
    private func delete(_ obligation: Obligation) {
        let model = model, profileId = profileId
        let message = ObligationForm.deletedMessage(obligation.name, in: locale)
        Task {
            do {
                let token = try await model.deleteObligation(obligation, profileId: profileId)
                toast = UndoToast(message, length: .long) {
                    Task {
                        do {
                            try await model.restoreObligation(token)
                        } catch {
                            log.error("Restoring a payment failed: \(String(describing: error))")
                        }
                    }
                }
            } catch {
                log.error("Deleting a payment failed: \(String(describing: error))")
                failed = true
            }
        }
    }

    /// The snapshots end once the profile is gone, and that closes the screen. A participant
    /// leaves rather than deletes: the profile goes from this phone only.
    private func deleteProfile(leaving: Bool) {
        let model = model, profileId = profileId
        Task {
            do {
                if leaving {
                    try await model.leaveProfile(profileId)
                } else {
                    try await model.deleteProfile(profileId)
                }
            } catch {
                log.error("Deleting a profile failed: \(String(describing: error))")
                failed = true
            }
        }
    }

    private func loadParticipants() async {
        do {
            participants = try await model.sync.participants(profileId)
        } catch {
            // Offline, say: the people iCloud named last stay on screen.
            log.notice("Reading who the profile is shared with failed: \(String(describing: error))")
        }
    }

    /// Everyone invited loses the profile; the owner keeps it.
    private func stopSharing() {
        let model = model, profileId = profileId, locale = locale
        Task {
            do {
                try await model.stopSharing(profileId)
                await loadParticipants()
            } catch {
                log.error("Stopping sharing failed: \(String(describing: error))")
                sharingFailure = SyncProblemText.text(SyncProblem(error), in: locale)
            }
        }
    }

    // MARK: Text

    static let nameTitle = LocalizedStringResource("Name", table: "Profiles", comment: "Name alert: the profile's name field.")
    static let activeTitle = LocalizedStringResource("Active on this phone", table: "Profiles", comment: "Profile screen: this profile is the one the whole app shows.")
    static let makeActiveTitle = LocalizedStringResource("Make active", table: "Profiles", comment: "Profile screen and list: opens this profile in the whole app.")
    static let activeNote = LocalizedStringResource(
        "What you record by hand or by voice goes to the active profile. The menu at the top of every tab switches it.",
        table: "Profiles", comment: "Profile screen: what the active profile is."
    )
    static let exchangeTitle = LocalizedStringResource("Exchange", table: "Profiles", comment: "Profile screen: the header over the markup over the CBR rate.")
    static let paymentsTitle = LocalizedStringResource("Payments", table: "Profiles", comment: "Profile screen: the header over the monthly payments.")
    static let paymentsNote = LocalizedStringResource(
        "Payments due before payday are set aside from “Safe to spend today”. A loan’s or a credit card’s payment is added when the debt counts in it.",
        table: "Profiles", comment: "Profile screen: what the monthly payments do."
    )
    static let addPaymentTitle = LocalizedStringResource("Payment", table: "Profiles", comment: "A payment: the title of the payment form when changing one, and the last row of the payments, “+ Payment”.")
    static let addPaymentLabel = LocalizedStringResource("Add payment", table: "Profiles", comment: "VoiceOver: the “+ Payment” row.")
    static let failureText = LocalizedStringResource("The change was not saved. Try again.", table: "Profiles", comment: "Profile screens: saving or deleting failed.")
}

/// A row's quiet glyph and its name, the way Android's settings rows start: the glyph in a column
/// of its own width, so the names of a group line up.
struct RowLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: Theme.Gap.m) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Color.muted)
                .frame(width: ProfileSymbols.width)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .foregroundStyle(Theme.Color.text)
        }
    }
}

/// An action row's glyph and title in one ink: the system blue for an action (D34), red for a
/// delete. The glyph stands in the same column as `RowLabel`'s, so the titles line up.
struct ActionRowLabel: View {
    let title: String
    let symbol: String
    let ink: AnyShapeStyle

    var body: some View {
        HStack(spacing: Theme.Gap.m) {
            Image(systemName: symbol)
                .frame(width: ProfileSymbols.width)
                .accessibilityHidden(true)
            Text(verbatim: title)
        }
        .foregroundStyle(ink)
    }
}

/// SF Symbols of the profile screens, Android's settings glyphs (D14). A test checks each one
/// exists, as `Symbols` does for the shared ones.
enum ProfileSymbols {
    static let profile = "person.crop.circle"
    static let name = "pencil"
    static let active = "checkmark.circle.fill"
    static let makeActive = "checkmark.circle"
    static let rate = "hourglass"
    static let taxHours = "timer"
    static let payday = "calendar"
    static let markup = "percent"
    static let payment = "calendar.badge.clock"
    static let invite = "person.crop.circle.badge.plus"
    static let stopSharing = "person.crop.circle.badge.xmark"
    static let leave = "rectangle.portrait.and.arrow.right"
    static let person = "person.circle"
    /// The column every row's glyph stands in.
    static let width: CGFloat = 28

    static let allNames = [profile, name, active, makeActive, rate, taxHours, payday, markup, payment, invite, stopSharing, leave, person]
}

#Preview("Samples") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let id = model.activeProfileId {
            ProfileScreen(profileId: id)
        }
    }
    .environment(model)
    .task { await model.start(command: .samples) }
}

#Preview("Samples, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let id = model.activeProfileId {
            ProfileScreen(profileId: id)
        }
    }
    .environment(model)
    .environment(\.locale, Locale(identifier: "ru"))
    .preferredColorScheme(.dark)
    .task { await model.start(command: .samples) }
}
