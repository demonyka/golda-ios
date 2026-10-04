import Foundation
import Testing

@testable import GoldaData

/// The shape of the real answer of the currency API (fetched 2026-10-04), cut down: units of each
/// currency per ruble under lowercase codes, with the crypto tokens, metals and old currencies the
/// API lists beside the real ones, and the ruble itself.
private let sampleAnswer = #"""
{"date":"2026-10-03","rub":{"1inch":0.11726372,"ars":18.19124897,"ats":0.14612846,"btc":1.4150555e-07,
 "clp":11.88570452,"kwd":0.0037074202,"mxn":0.2179779,"rub":1,"usd":0.012002436,"xau":2.9008639e-06}}
"""#

/// The source over the real session code, its two addresses answered by [replies] in turn.
private func source(_ first: StubURLProtocol.Reply, _ mirror: StubURLProtocol.Reply) -> CurrencyApiRatesSource {
    CurrencyApiRatesSource(
        transport: URLSessionTransport(session: StubURLProtocol.session()),
        urls: [StubURLProtocol.register(first), StubURLProtocol.register(mirror)]
    )
}

private func answer(_ body: String, status: Int = 200) -> StubURLProtocol.Reply {
    .answer(status: status, body: Data(body.utf8))
}

private let offline = StubURLProtocol.Reply.fail(URLError(.notConnectedToInternet))

@Suite struct CurrencyApiParsingTests {
    @Test func aRateIsRublesPerUnitTheInverseOfTheAnswer() async throws {
        let rates = try await source(answer(sampleAnswer), offline).fetch()
        let byCode = Dictionary(uniqueKeysWithValues: rates.map { ($0.code, $0.rubPerUnit) })
        #expect(byCode["ARS"] == 1 / 18.19124897)
        #expect(byCode["KWD"] == 1 / 0.0037074202)
        #expect(rates.allSatisfy { $0.date == "2026-10-03" })
    }

    @Test func onlyCurrenciesOfTheCatalogueComeBackByCode() async throws {
        // No crypto, no gold, no schilling, and no ruble: the Bank of Russia's 1.0 is the one.
        let rates = try await source(answer(sampleAnswer), offline).fetch()
        #expect(rates.map(\.code) == ["ARS", "CLP", "KWD", "MXN", "USD"])
    }

    @Test func aBadValueLeavesOutThatCurrencyAlone() async throws {
        // Hundreds of entries the app never reads: one of them must not cost the pesos their rate.
        let body = #"{"date":"2026-10-03","rub":{"ars":18.2,"mxn":0,"clp":-1,"cop":null,"pen":"0.05","doge":"x","usd":0.012}}"#
        let rates = try await source(answer(body), offline).fetch()
        #expect(rates.map(\.code) == ["ARS", "USD"])
    }

    @Test func asksWithTenSecondTimeoutsAndNoCache() async throws {
        let log = RequestLog()
        let transport = StubHTTPTransport { request in
            log.record(request)
            return (Data(sampleAnswer.utf8), 200)
        }
        _ = try await CurrencyApiRatesSource(transport: transport).fetch()

        let request = try #require(log.all.first)
        #expect(log.all.count == 1)
        #expect(request.url?.absoluteString == "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/rub.json")
        #expect(request.timeoutInterval == 10)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func theMirrorIsTheAPIsOwnFallback() {
        #expect(CurrencyApiRatesSource.endpoints.map(\.absoluteString) == [
            "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/rub.json",
            "https://latest.currency-api.pages.dev/v1/currencies/rub.json",
        ])
    }
}

@Suite struct CurrencyApiFallbackTests {
    @Test(arguments: [
        offline,
        StubURLProtocol.Reply.fail(URLError(.timedOut)),
        answer(sampleAnswer, status: 503),
        answer("<html>502 Bad Gateway</html>"),
    ])
    func theMirrorAnswersWhenTheFirstAddressCannot(first: StubURLProtocol.Reply) async throws {
        let mirrored = sampleAnswer.replacingOccurrences(of: "2026-10-03", with: "2026-10-04")
        let rates = try await source(first, answer(mirrored)).fetch()
        #expect(rates.map(\.code) == ["ARS", "CLP", "KWD", "MXN", "USD"])
        #expect(rates.allSatisfy { $0.date == "2026-10-04" })
    }

    @Test func theMirrorIsNotAskedWhenTheFirstAddressAnswers() async throws {
        let log = RequestLog()
        let transport = StubHTTPTransport { request in
            log.record(request)
            return (Data(sampleAnswer.utf8), 200)
        }
        _ = try await CurrencyApiRatesSource(transport: transport).fetch()
        #expect(log.all.count == 1)
    }

    @Test func offlineEverywhereThrowsTheURLError() async {
        await #expect {
            try await source(offline, offline).fetch()
        } throws: { error in
            (error as? URLError)?.code == .notConnectedToInternet
        }
    }

    @Test(arguments: [
        "<html>502 Bad Gateway</html>",
        "",
        "[]",
        "{}",
        #"{"date":"2026-10-03"}"#,
        #"{"rub":{"ars":18.2}}"#,
        #"{"date":"2026-10-03","rub":[]}"#,
        #"{"date":20261003,"rub":{"ars":18.2}}"#,
        #"{"date":"2026-10-03","usd":{"ars":1400}}"#,
    ])
    func aBrokenAnswerFromBothAddressesFails(body: String) async {
        await #expect(throws: CurrencyApiError.malformed) {
            try await source(answer(body), answer(body)).fetch()
        }
    }

    @Test func anErrorStatusFromBothAddressesFails() async {
        await #expect(throws: CurrencyApiError.http(status: 404)) {
            try await source(answer(sampleAnswer, status: 500), answer(sampleAnswer, status: 404)).fetch()
        }
    }
}

/// The Bank of Russia stays the source of its currencies; the second one only fills the gaps.
@Suite struct MergedRatesTests {
    private let cbr = StubRatesSource {
        [
            CbrRate(code: "USD", rubPerUnit: 83.4839, date: "2026-10-03"),
            CbrRate(code: "RUB", rubPerUnit: 1.0, date: "2026-10-03"),
        ]
    }
    private let supplement = StubRatesSource {
        [
            CbrRate(code: "ARS", rubPerUnit: 0.055, date: "2026-10-04"),
            CbrRate(code: "USD", rubPerUnit: 80.0, date: "2026-10-04"),
        ]
    }

    @Test func theSecondSourceFillsOnlyWhatTheBankLacks() async throws {
        let rates = try await MergedRatesSource(official: cbr, supplement: supplement).fetch()
        #expect(rates.first { $0.code == "USD" }?.rubPerUnit == 83.4839)
        #expect(rates.filter { $0.code == "USD" }.count == 1)
        #expect(rates.first { $0.code == "ARS" }?.rubPerUnit == 0.055)
    }

    @Test func theFilledRatesCarryTheBanksDay() async throws {
        // Settings names the day as "ЦБ на …", the newest in the table: the second source's own day
        // would claim a Bank of Russia rate that is not there.
        let rates = try await MergedRatesSource(official: cbr, supplement: supplement).fetch()
        #expect(rates.allSatisfy { $0.date == "2026-10-03" })
    }

    @Test func aFailingSecondSourceLeavesTheBanksRates() async throws {
        let broken = StubRatesSource { throw CurrencyApiError.malformed }
        let rates = try await MergedRatesSource(official: cbr, supplement: broken).fetch()
        #expect(rates == (try await cbr.fetch()))
    }

    @Test func aFailingBankFailsTheRefreshWhateverTheSecondSourceSays() async {
        let down = StubRatesSource { throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await MergedRatesSource(official: down, supplement: supplement).fetch()
        }
    }
}

/// A refresh through both sources, into the table.
@Suite struct MergedRatesRefreshTests {
    @Test func pesosGetARateAndARefreshWithoutTheSecondSourceKeepsIt() async throws {
        let harness = try RepositoryHarness()
        let cbr = StubRatesSource { [CbrRate(code: "USD", rubPerUnit: 84, date: "2026-10-03"), CbrRate(code: "RUB", rubPerUnit: 1, date: "2026-10-03")] }
        let pesos = StubRatesSource { [CbrRate(code: "ARS", rubPerUnit: 0.055, date: "2026-10-04")] }
        #expect(try await harness.repository.refreshRates(from: MergedRatesSource(official: cbr, supplement: pesos)))

        var table = try await harness.database.read { try $0.rates() }
        #expect(table.first { $0.code == "ARS" } == RateRecord(code: "ARS", rubPerUnit: 0.055, date: "2026-10-03"))

        let down = StubRatesSource { throw URLError(.notConnectedToInternet) }
        let nextDay = StubRatesSource { [CbrRate(code: "USD", rubPerUnit: 85, date: "2026-10-04"), CbrRate(code: "RUB", rubPerUnit: 1, date: "2026-10-04")] }
        #expect(try await harness.repository.refreshRates(from: MergedRatesSource(official: nextDay, supplement: down)))
        table = try await harness.database.read { try $0.rates() }
        #expect(table.first { $0.code == "USD" }?.rubPerUnit == 85)
        #expect(table.first { $0.code == "ARS" }?.rubPerUnit == 0.055, "the last rate there was stays")
    }
}
