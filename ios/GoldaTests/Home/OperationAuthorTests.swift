import Foundation
import GoldaCore
import GoldaSync
import Testing

@testable import Golda

/// D67: in a profile shared with someone, each operation says who wrote it, by the name iCloud
/// knows them by; this person's own read "Вы". Who created a record is the server's to say.
@MainActor @Suite struct OperationAuthorTests {
    typealias F = HomeFixture
    var books = HomeFixture()
    let me = "__defaultOwner__"
    let mine = UUID(), hers = UUID(), local = UUID(), stranger = UUID()

    var people: [SyncParticipant] {
        [
            SyncParticipant(id: "_owner", name: "Dmitrii Isaev", shortName: "Dmitrii", isOwner: true, isCurrentUser: true, status: .joined, canWrite: true),
            SyncParticipant(id: "_wife", name: "Лекла Хасанова", shortName: "Лекла", isOwner: false, isCurrentUser: false, status: .joined, canWrite: true),
        ]
    }

    @Test func eachOperationHasItsWriter() {
        let authorship = Authorship.resolve(
            operations: [mine, hers, local, stranger],
            creators: [mine: me, hers: "_wife", stranger: "_someone"],
            participants: people, currentUser: me
        )
        #expect(authorship?.byOperation[mine] == .me)
        #expect(authorship?.byOperation[hers] == .person("Лекла"))
        // Not on the server yet: written here.
        #expect(authorship?.byOperation[local] == .me)
        // Someone the share does not list (left since): no name rather than a wrong one.
        #expect(authorship?.byOperation[stranger] == nil)
    }

    @Test func thisPersonByTheirOwnRecordNameIsThemToo() {
        let authorship = Authorship.resolve(operations: [mine], creators: [mine: "_owner"], participants: people, currentUser: me)
        #expect(authorship?.byOperation[mine] == .me)
    }

    @Test func aNameIsTheShortOneThenTheFullOne() {
        var named = people
        named[1].shortName = nil
        let authorship = Authorship.resolve(operations: [hers], creators: [hers: "_wife"], participants: named, currentUser: me)
        #expect(authorship?.byOperation[hers] == .person("Лекла Хасанова"))
        named[1].name = nil
        #expect(Authorship.resolve(operations: [hers], creators: [hers: "_wife"], participants: named, currentUser: me)?.byOperation[hers] == nil)
    }

    @Test func aProfileNoOneElseIsInSaysNoNames() {
        let alone = [people[0]]
        #expect(Authorship.resolve(operations: [mine], creators: [:], participants: alone, currentUser: me) == nil)
        // Invited but not joined yet: still alone.
        var invited = people
        invited[1].status = .invited
        #expect(Authorship.resolve(operations: [mine], creators: [:], participants: invited, currentUser: me) == nil)
    }

    @Test func theRowSaysTheNameUnderTheTitle() throws {
        let coffee = F.operation(.expense, at: F.at(hour: 9), note: "Кофе", [(books.rub, -15_000, -15_000)])
        let shawarma = F.operation(.expense, at: F.at(hour: 10), note: "Шаурма", [(books.cash, -1_500, -1_500)])
        var data = books.data
        data.authorship = Authorship(byOperation: [coffee.op.id: .me, shawarma.op.id: .person("Лекла")])
        let mine = try #require(OperationRowModel(coffee, in: data))
        #expect(mine.supportingText(in: F.ru) == "Вы")
        #expect(mine.supportingText(in: F.en) == "You")
        // After the account it was paid from, when that is not the usual one.
        let hers = try #require(OperationRowModel(shawarma, in: data))
        #expect(hers.supportingText(in: F.ru) == "Наличные ₾ · Лекла")
        #expect(hers.accessibilityLabel(in: F.ru).hasPrefix("Шаурма, Наличные ₾ · Лекла, "))
        // Not shared: no names.
        #expect(try books.row(coffee).supportingText(in: F.ru) == nil)
    }
}
