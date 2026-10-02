import Foundation
import Testing

@testable import GoldaData

/// The shape of the real answer of cbr-xml-daily.ru (fetched 2026-10-02), cut down to four
/// currencies: a time in `Date`, the extra fields CBR sends, and nominals of 1, 10 and 100.
private let sampleAnswer = #"""
{"Date":"2026-10-03T11:30:00+03:00","PreviousDate":"2026-10-02T11:30:00+03:00",
 "PreviousURL":"\/\/www.cbr-xml-daily.ru\/archive\/2026\/10\/02\/daily_json.js",
 "Timestamp":"2026-10-02T20:00:00+03:00",
 "Valute":{
  "AMD":{"ID":"R01060","NumCode":"051","CharCode":"AMD","Nominal":100,"Name":"Армянских драмов","Value":23.0269,"Previous":22.944},
  "USD":{"ID":"R01235","NumCode":"840","CharCode":"USD","Nominal":1,"Name":"Доллар США","Value":83.4839,"Previous":83.2454},
  "GEL":{"ID":"R01210","NumCode":"981","CharCode":"GEL","Nominal":1,"Name":"Лари","Value":32.0574,"Previous":31.9597},
  "THB":{"ID":"R01675","NumCode":"764","CharCode":"THB","Nominal":10,"Name":"Батов","Value":24.8146,"Previous":24.7438}
 }}
"""#

/// Remembers the requests a stub transport received.
private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var all: [URLRequest] { lock.withLock { requests } }
}

private func source(status: Int = 200, body: String = sampleAnswer) -> CbrRatesSource {
    CbrRatesSource(transport: StubHTTPTransport(status: status, body: Data(body.utf8)))
}

@Suite struct CbrParsingTests {
    @Test func aRateIsTheValuePerNominalUnit() async throws {
        let rates = try await source().fetch()
        let byCode = Dictionary(uniqueKeysWithValues: rates.map { ($0.code, $0.rubPerUnit) })
        #expect(byCode["USD"] == 83.4839)
        #expect(byCode["GEL"] == 32.0574)
        #expect(byCode["THB"] == 24.8146 / 10)
        #expect(byCode["AMD"] == 23.0269 / 100)
    }

    @Test func theDateIsTheFirstTenCharactersOfDate() async throws {
        let rates = try await source().fetch()
        #expect(rates.allSatisfy { $0.date == "2026-10-03" })
    }

    @Test func theRubleIsAddedAtOneAndComesLast() async throws {
        let rates = try await source().fetch()
        #expect(rates.count == 5)
        #expect(rates.last == CbrRate(code: "RUB", rubPerUnit: 1.0, date: "2026-10-03"))
        #expect(rates.filter { $0.code == "RUB" }.count == 1)
    }

    @Test func ratesComeInAStableOrder() async throws {
        let rates = try await source().fetch()
        #expect(rates.map(\.code) == ["AMD", "GEL", "THB", "USD", "RUB"])
    }

    @Test func noCurrenciesLeavesJustTheRuble() async throws {
        let rates = try await source(body: #"{"Date":"2026-10-03T11:30:00+03:00","Valute":{}}"#).fetch()
        #expect(rates == [CbrRate(code: "RUB", rubPerUnit: 1.0, date: "2026-10-03")])
    }

    @Test func aShortDateIsTakenAsItIs() async throws {
        let rates = try await source(body: #"{"Date":"2026-10","Valute":{}}"#).fetch()
        #expect(rates.first?.date == "2026-10")
    }

    @Test func aDecimalNominalAndAnyKeyOrderParse() async throws {
        // Kotlin's getInt took 1.0 for 1, and a JSON object has no order to rely on.
        let body = #"{"Valute":{"USD":{"Value":83.4839,"Nominal":1.0}},"Date":"2026-10-03T11:30:00+03:00"}"#
        let rates = try await source(body: body).fetch()
        #expect(rates.first == CbrRate(code: "USD", rubPerUnit: 83.4839, date: "2026-10-03"))
    }
}

@Suite struct CbrRequestTests {
    @Test func asksTheMirrorWithTenSecondTimeouts() async throws {
        let log = RequestLog()
        let transport = StubHTTPTransport { request in
            log.record(request)
            return (Data(sampleAnswer.utf8), 200)
        }
        _ = try await CbrRatesSource(transport: transport).fetch()

        let request = try #require(log.all.first)
        #expect(log.all.count == 1)
        #expect(request.url?.absoluteString == "https://www.cbr-xml-daily.ru/daily_json.js")
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 10)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func theFallbackIsTheOneFromAndroid() {
        #expect(CbrRatesSource.fallback == [
            CbrRate(code: "RUB", rubPerUnit: 1.0, date: "2026-10-02"),
            CbrRate(code: "USD", rubPerUnit: 83.2454, date: "2026-10-02"),
            CbrRate(code: "GEL", rubPerUnit: 31.9597, date: "2026-10-02"),
            CbrRate(code: "THB", rubPerUnit: 2.47438, date: "2026-10-02"),
        ])
    }
}

@Suite struct CbrFailureTests {
    @Test(arguments: [301, 400, 404, 500, 503])
    func anErrorStatusFails(status: Int) async {
        // The body is valid on purpose: the status alone must decide.
        await #expect(throws: CbrError.http(status: status)) {
            try await source(status: status).fetch()
        }
    }

    @Test(arguments: [
        "<html>502 Bad Gateway</html>",
        "",
        "[]",
        "{}",
        #"{"Date":"2026-10-03"}"#,
        #"{"Valute":{}}"#,
        #"{"Date":"2026-10-03T11:30:00+03:00","Valute":{"USD":{"Nominal":1}}}"#,
        #"{"Date":"2026-10-03T11:30:00+03:00","Valute":{"USD":{"Value":83.4}}}"#,
        #"{"Date":"2026-10-03T11:30:00+03:00","Valute":{"USD":{"Value":"83.4","Nominal":1}}}"#,
        #"{"Date":"2026-10-03T11:30:00+03:00","Valute":{"USD":{"Value":83.4,"Nominal":0}}}"#,
        #"{"Date":"2026-10-03T11:30:00+03:00","Valute":[]}"#,
    ])
    func aBrokenAnswerFails(body: String) async {
        await #expect(throws: CbrError.malformed) {
            try await source(body: body).fetch()
        }
    }

    @Test func oneBadCurrencySpoilsTheWholeAnswer() async {
        // Like Android: a half-read list is worse than the fallback.
        let body = #"{"Date":"2026-10-03T11:30:00+03:00","Valute":{"USD":{"Value":83.4,"Nominal":1},"XXX":{"Value":1,"Nominal":0}}}"#
        await #expect(throws: CbrError.malformed) {
            try await source(body: body).fetch()
        }
    }

    @Test func noNetworkPassesTheURLErrorThrough() async {
        let offline = CbrRatesSource(transport: StubHTTPTransport(error: URLError(.notConnectedToInternet)))
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await offline.fetch()
        }
    }

    @Test func aTimeoutPassesTheURLErrorThrough() async {
        let slow = CbrRatesSource(transport: StubHTTPTransport(error: URLError(.timedOut)))
        await #expect(throws: URLError(.timedOut)) {
            try await slow.fetch()
        }
    }
}

/// `URLSessionTransport` against a `URLProtocol` stub: the real session code runs, no socket opens.
@Suite struct URLSessionTransportTests {
    @Test func returnsTheBodyAndTheResponse() async throws {
        let url = StubURLProtocol.register(.answer(status: 200, body: Data(sampleAnswer.utf8)))
        let transport = URLSessionTransport(session: StubURLProtocol.session())

        let (data, response) = try await transport.send(URLRequest(url: url))
        #expect(response.statusCode == 200)
        #expect(data == Data(sampleAnswer.utf8))
    }

    @Test func anErrorStatusIsAResponseNotAThrow() async throws {
        let url = StubURLProtocol.register(.answer(status: 503, body: Data()))
        let (_, response) = try await URLSessionTransport(session: StubURLProtocol.session()).send(URLRequest(url: url))
        #expect(response.statusCode == 503)
    }

    @Test func aFailedConnectionThrowsTheURLError() async {
        let url = StubURLProtocol.register(.fail(URLError(.notConnectedToInternet)))
        let transport = URLSessionTransport(session: StubURLProtocol.session())
        // URLSession adds task details to the error, so compare the code, not the whole value.
        await #expect {
            try await transport.send(URLRequest(url: url))
        } throws: { error in
            (error as? URLError)?.code == .notConnectedToInternet
        }
    }

    @Test func theSourceWorksOverTheRealSessionCode() async throws {
        let url = StubURLProtocol.register(.answer(status: 200, body: Data(sampleAnswer.utf8)))
        let source = CbrRatesSource(transport: URLSessionTransport(session: StubURLProtocol.session()), url: url)
        let rates = try await source.fetch()
        #expect(rates.count == 5)
        #expect(rates.first { $0.code == "USD" }?.rubPerUnit == 83.4839)
    }
}

/// Answers requests from a table keyed by URL. Every test registers a URL of its own, so tests may run in parallel.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case answer(status: Int, body: Data)
        case fail(URLError)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [URL: Reply] = [:]

    static func register(_ reply: Reply) -> URL {
        let url = URL(string: "https://stub.golda.test/\(UUID().uuidString)")!
        lock.withLock { replies[url] = reply }
        return url
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let reply = Self.lock.withLock({ Self.replies[url] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch reply {
        case .answer(let status, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
