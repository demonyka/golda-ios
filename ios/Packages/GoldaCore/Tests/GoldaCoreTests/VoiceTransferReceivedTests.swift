import Foundation
import Testing

@testable import GoldaCore

/// A transfer the model answered with only the amount that arrived (D46, unlike Android):
/// gemini-3.5-flash-lite puts «перевёл с карты на накопительный 80000 рублей» into `to_amount`,
/// every time. That amount is the destination's, in its currency; what left the source follows
/// from it.
@Suite struct VoiceTransferReceivedTests {
    let rates = Rates(["USD": 83.2454, "GEL": 31.9597], markup: 0.10)
    let rubCard = Account(id: uid(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    let multiUsd = Account(id: uid(2), name: "Мультивалютная USD", currency: "USD", type: .card, includeInFree: true, sort: 1)
    let savings = Account(id: uid(3), name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, sort: 2)
    let now = LocalDate(2026, 10, 3).atTimeMillis(hour: 20, in: utc)

    func actions(_ item: VoiceItem) -> [VoiceAction] {
        VoiceMapper.actions(
            VoiceResult(transcript: "…", items: [item]), accounts: [rubCard, multiUsd, savings], categories: [],
            settings: Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL"), rates: rates,
            recordedAt: now, zone: utc
        )
    }

    func draft(_ item: VoiceItem) throws -> Draft {
        guard case .record(let draft) = actions(item).first else { throw Failure() }
        return draft
    }

    struct Failure: Error {}

    /// Gemini's own answer to the phrase above.
    @Test func onlyTheReceivedAmountBetweenRubleAccountsMovesThatAmount() throws {
        let d = try draft(VoiceItem(intent: "transfer", note: "", accountId: "1", toAccountId: "3", toAmount: "80000.00"))
        #expect(d.accountId == rubCard.id && d.toAccountId == savings.id)
        #expect(d.amountMinor == 8_000_000)
        #expect(d.toAmountMinor == 8_000_000)
        #expect(!d.isEstimate)
    }

    /// The dollars arrived as said; the rubles that left are the bank's guess until reconciled.
    @Test func onlyTheReceivedAmountInAnotherCurrencyEstimatesWhatLeft() throws {
        let d = try draft(VoiceItem(intent: "transfer", note: "", accountId: "1", toAccountId: "2", toAmount: "100"))
        #expect(d.toAmountMinor == 10_000)
        #expect(d.amountMinor == rates.convert(10_000, from: "USD", to: "RUB"))
        #expect(d.isEstimate)
    }

    @Test func aTransferWithNoAmountAtAllIsStillNotUnderstood() {
        guard case .notUnderstood = actions(VoiceItem(intent: "transfer", note: "", accountId: "1", toAccountId: "3")).first else {
            Issue.record("expected notUnderstood")
            return
        }
    }
}
