import Foundation
import GoldaCore
import GoldaData
import GoldaSync
import Synchronization
import Testing

@testable import Golda

/// What the profile's screen offers about sharing, from who owns the profile, whether iCloud is
/// there and who is in it (stage 5c).
@Suite struct ProfileSharingTests {
    private let ru = Locale(identifier: "ru")
    private let owner = SyncParticipant(id: "a", name: "Алиса", isOwner: true, isCurrentUser: false, status: .joined, canWrite: true)
    private let me = SyncParticipant(id: "me", name: "Я", isOwner: false, isCurrentUser: true, status: .joined, canWrite: true)
    private let bob = SyncParticipant(id: "b", name: "Боб", isOwner: false, isCurrentUser: false, status: .joined, canWrite: true)
    private let pending = SyncParticipant(id: "c", name: nil, isOwner: false, isCurrentUser: false, status: .invited, canWrite: false)

    @Test func withoutICloudTheOwnerIsToldWhyThereIsNoInvite() {
        for availability in [AppSync.Availability.off, .noICloud] {
            let sharing = ProfileSharing(role: .owner, availability: availability, participants: [])
            #expect(!sharing.canInvite)
            #expect(!sharing.canStopSharing)
            #expect(sharing.canDelete)
            #expect(sharing.note(in: ru) == ProfileSharing.noICloudNote.text(in: ru))
        }
    }

    @Test func theOwnerInvitesAndOnceSomeoneJoinedMayStopSharing() {
        let alone = ProfileSharing(role: .owner, availability: .on, participants: [])
        #expect(alone.canInvite)
        #expect(!alone.canStopSharing)
        #expect(!alone.isShared)
        #expect(alone.deletionKind == .notShared)

        let ownerMe = SyncParticipant(id: "me", name: "Я", isOwner: true, isCurrentUser: true, status: .joined, canWrite: true)
        let shared = ProfileSharing(role: .owner, availability: .on, participants: [pending, bob, ownerMe])
        #expect(shared.canStopSharing)
        #expect(shared.isShared)
        #expect(shared.deletionKind == .sharedByMe)
        // This person is not listed; the others are, the one who has not joined says so.
        #expect(shared.people.map(\.id) == ["b", "c"])
        #expect(ProfileSharing.name(of: pending, in: ru) == "Приглашённый")
        #expect(ProfileSharing.detail(of: pending, in: ru) == "Приглашение ещё не принято")
        #expect(ProfileSharing.detail(of: bob, in: ru) == nil)
    }

    @Test func aParticipantLeavesAndSeesTheOwner() {
        let sharing = ProfileSharing(role: .participant, availability: .on, participants: [me, bob, owner])
        #expect(sharing.canLeave)
        #expect(!sharing.canInvite)
        #expect(!sharing.canDelete)
        #expect(sharing.deletionKind == .sharedWithMe)
        #expect(sharing.people.first == owner)
        #expect(ProfileSharing.detail(of: owner, in: ru) == "Владелец")
        #expect(sharing.note(in: ru).contains("Алиса"))
        // Leaving works offline too: the server hears later.
        #expect(ProfileSharing(role: .participant, availability: .noICloud, participants: []).canLeave)
    }

    /// The owner's first share on 2026-10-04: "retry after 330 s" is said in minutes (D58).
    @Test func iCloudProblemsAreSaidInWords() {
        let wait = ProfileSharing(role: .owner, availability: .on, participants: [], problem: .retryLater(seconds: 330))
        #expect(wait.note(in: ru) == "iCloud попросил подождать. Попробуйте через 6 мин.")
        #expect(SyncProblemText.text(.retryLater(seconds: 1), in: Locale(identifier: "en")) == "iCloud asked to wait. Try again in 1 min.")
        #expect(SyncProblemText.text(.iCloudFull, in: ru).hasPrefix("Хранилище iCloud заполнено"))
        #expect(SyncProblemText.text(.other(code: 15), in: ru).contains("15"))
        for problem in [SyncProblem.noAccount, .iCloudFull, .offline, .notPermitted, .other(code: 1)] {
            #expect(SyncProblemText.text(problem, in: ru) != SyncProblemText.text(problem, in: Locale(identifier: "en")))
        }
    }

    @Test func leavingAndSharedDeletionsAskTheirOwnQuestion() {
        let leave = ProfileDeletion(name: "Семья", contents: nil, sharing: .sharedWithMe)
        #expect(leave.title(in: ru) == "Выйти из «Семья»?")
        #expect(leave.confirmAction.text(in: ru) == "Выйти")
        #expect(leave.message(in: ru).contains("у владельца он останется"))
        let shared = ProfileDeletion(name: "Семья", contents: ProfileContents(accounts: 1), sharing: .sharedByMe)
        #expect(shared.title(in: ru) == "Удалить «Семья»?")
        #expect(shared.message(in: ru).hasSuffix("Он пропадёт и у всех, с кем вы им поделились."))
    }
}

/// Sync and sharing over the real app model, two phones on one in-memory cloud: what the owner
/// writes shows on the participant's Home, leaving and stopping sharing take the profile away.
@MainActor @Suite(.timeLimit(.minutes(1))) struct AppSyncTests {
    private let cloud = InMemoryCloud()

    private func phone(_ user: String, status: SyncAccountStatus = .available) async throws -> AppHarness {
        let cloud = cloud
        let harness = try AppHarness(syncBackend: .custom { store in
            let transport = InMemorySyncTransport(cloud: cloud, user: user, store: store, now: { AppHarness.now })
            Task { await transport.setStatus(status) }
            return transport
        })
        // The transport's status lands before the launch asks for it.
        await Task.yield()
        return harness
    }

    private func launch(_ harness: AppHarness, profile: String? = nil) async throws -> UUID? {
        await harness.model.start()
        var id: UUID?
        if let profile { id = try await harness.profile(profile) }
        harness.onboard(active: id)
        try await Task.sleep(for: .milliseconds(20))
        await harness.model.sync.start()
        return id
    }

    private func sync(_ phones: AppHarness...) async throws {
        for phone in phones {
            try await phone.model.sync.service?.syncNow()
        }
    }

    @Test func anInMemoryRunDoesNotSync() async throws {
        let harness = try AppHarness()
        await harness.model.sync.start()
        #expect(harness.model.sync.availability == .off)
        #expect(harness.model.sync.invitation(for: UUID(), title: "x") == nil)
    }

    @Test func withoutAnAccountTheBooksStayLocal() async throws {
        let alice = try await phone("alice", status: .noAccount)
        let personal = try #require(try await launch(alice, profile: "Личный"))
        await eventually { alice.model.sync.availability == .noICloud }
        #expect(alice.model.sync.problem == .noAccount)
        #expect(!(await cloud.hasZone(personal, of: "alice")))
    }

    @Test func theParticipantSeesTheOwnersBooksAndTheSameSafeToSpend() async throws {
        let alice = try await phone("alice")
        let bob = try await phone("bob")
        let family = try #require(try await launch(alice, profile: "Семья"))
        let bobs = try #require(try await launch(bob, profile: "Личный"))
        let card = Account.card("Общая карта")
        try await alice.repository.saveAccount(card, profileId: family, openingMinor: 3_000_000)
        try await alice.repository.save(Draft(type: .expense, timestamp: AppHarness.now, accountId: card.id, amountMinor: 120_000), profileId: family)
        try await sync(alice)
        await cloud.share(family, of: "alice", with: "bob")
        try await sync(bob)

        await eventually { bob.model.profiles.map(\.name) == ["Личный", "Семья"] }
        await eventually { bob.model.sync.isParticipant(in: family) }
        #expect(!alice.model.sync.isParticipant(in: family))
        #expect(bob.model.activeProfileId == bobs)

        bob.model.switchProfile(to: family)
        await eventually { bob.model.data?.profile.id == family }
        let atAlice = try #require(alice.model.data.map { HomeHero(data: $0, today: alice.environment.today()) })
        let atBob = try #require(bob.model.data.map { HomeHero(data: $0, today: bob.environment.today()) })
        #expect(atAlice.leftMinor == atBob.leftMinor)
        #expect(atAlice.budget == atBob.budget)
        #expect(try await bob.model.sync.participants(family).map(\.name) == ["alice", "bob"])
    }

    @Test func leavingTakesTheProfileFromThisPhoneOnlyAndOpensAnother() async throws {
        let alice = try await phone("alice")
        let bob = try await phone("bob")
        let family = try #require(try await launch(alice, profile: "Семья"))
        let bobs = try #require(try await launch(bob, profile: "Личный"))
        try await sync(alice)
        await cloud.share(family, of: "alice", with: "bob")
        try await sync(bob)
        await eventually { bob.model.profiles.count == 2 }
        bob.model.switchProfile(to: family)

        try await bob.model.leaveProfile(family)
        await eventually { bob.model.activeProfileId == bobs }
        #expect(bob.model.profiles.map(\.id) == [bobs])
        try await sync(bob, alice)
        #expect(try await alice.model.sync.participants(family).isEmpty)
        #expect(alice.model.profiles.map(\.id) == [family])
    }

    @Test func stoppingSharingLeavesTheParticipantAFreshProfileWhenItWasTheirOnly() async throws {
        let alice = try await phone("alice")
        let bob = try await phone("bob")
        let family = try #require(try await launch(alice, profile: "Семья"))
        try await sync(alice)
        // Bob joined, then deleted his own profile: the shared one is his only one.
        let bobs = try #require(try await launch(bob, profile: "Личный"))
        await cloud.share(family, of: "alice", with: "bob")
        try await sync(bob)
        await eventually { bob.model.profiles.count == 2 }
        try await bob.model.deleteProfile(bobs)
        await eventually { bob.model.profiles.map(\.id) == [family] }

        try await alice.model.stopSharing(family)
        try await sync(bob)
        await eventually { bob.model.profiles.map(\.name) == [AppModel.firstProfileName] }
        #expect(alice.model.profiles.map(\.id) == [family])
    }
}
