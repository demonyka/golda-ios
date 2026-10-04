import Foundation
import Testing

@testable import GoldaCore

@Suite struct VoicePromptTests {
    @Test func theSchemaIsValidJSONWithTheExpectedIntents() throws {
        let object = try JSONSerialization.jsonObject(with: Data(VoicePrompt.schema.utf8)) as? [String: Any]
        let properties = try #require(object?["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["transcript", "items"])
        #expect(VoicePrompt.schema.contains("\"enum\":[\"expense\",\"income\",\"transfer\",\"consider\",\"unknown\"]"))
    }

    @Test func accountsAreNumberedByPositionInTheListGiven() {
        let accounts = [
            Account(id: uid(9), name: "Карта", currency: "RUB", type: .card, includeInFree: true),
            Account(id: uid(7), name: "Кредит", currency: "RUB", type: .loan, includeInFree: false),
        ]
        let prompt = VoicePrompt.system(accounts: accounts, categories: Category.builtIn, settings: Settings(), today: LocalDate(2026, 10, 2))
        #expect(prompt.contains("- 1: Карта, RUB, card"))
        #expect(prompt.contains("- 2: Кредит, RUB, loan"))
        #expect(prompt.contains("Сегодня 2026-10-02 (пятница)."))
        #expect(prompt.contains("- RUB — российский рубль"))
        #expect(prompt.contains("- USD — доллар США"))
        #expect(!prompt.contains(uid(9).uuidString))
        // The same positions come back as ids.
        let item = VoiceItem(intent: "expense", amount: "10", currency: "RUB", note: "кофе", accountId: "2")
        let actions = VoiceMapper.actions(VoiceResult(transcript: "", items: [item]), accounts: accounts, categories: Category.builtIn, settings: Settings(), rates: Rates([:], markup: 0), recordedAt: 0, zone: utc)
        guard case .record(let draft) = actions[0] else { Issue.record("expected a record"); return }
        #expect(draft.accountId == uid(7))
    }

    /// «Полтора» next to the amounts made the model hear «1000 песо» as "1500" now and then (owner,
    /// on the iPhone): the prompt gives no example that multiplies what was said.
    @Test func noExampleTurnsAnAmountIntoOneAndAHalf() {
        let prompt = VoicePrompt.system(accounts: [], categories: Category.builtIn, settings: Settings(), today: LocalDate(2026, 10, 4))
        #expect(!prompt.contains("полтор"))
        #expect(!prompt.contains("\"1.5\""))
    }

    @Test func unnamedPurchasesGetTheCallersTitle() {
        let item = VoiceItem(intent: "consider", amount: "50", currency: "USD", note: "  ")
        let actions = VoiceMapper.actions(VoiceResult(transcript: "", items: [item]), accounts: [], categories: [], settings: Settings(), rates: Rates([:], markup: 0), recordedAt: 0, zone: utc, unnamedPurchase: "Покупка")
        #expect(actions == [.consider(Consider(title: "Покупка", amountMinor: 5_000, currency: "USD"))])
    }

    @Test func theBuiltInCategoriesAreComplete() {
        #expect(Category.builtIn.filter { $0.kind == .expense }.count == 12)
        #expect(Category.builtIn.filter { $0.kind == .income }.count == 4)
        #expect(Set(Category.builtIn.map(\.key)).count == 16)
    }
}
