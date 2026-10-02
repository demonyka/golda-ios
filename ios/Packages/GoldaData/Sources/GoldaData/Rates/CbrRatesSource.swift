import Foundation

public enum CbrError: Error, Equatable, Sendable {
    /// The server answered with a status outside 2xx.
    case http(status: Int)
    /// The answer was not the JSON we expect: broken text, a missing field or a nominal that is not positive.
    case malformed
}

/// Official daily rates of the Bank of Russia, mirrored as JSON (port of Android's `Cbr.kt`).
public struct CbrRatesSource: RatesSource {
    public static let endpoint = URL(string: "https://www.cbr-xml-daily.ru/daily_json.js")!

    /// Used until the first successful download (CBR, 2026-10-02).
    public static let fallback: [CbrRate] = [
        CbrRate(code: "RUB", rubPerUnit: 1.0, date: "2026-10-02"),
        CbrRate(code: "USD", rubPerUnit: 83.2454, date: "2026-10-02"),
        CbrRate(code: "GEL", rubPerUnit: 31.9597, date: "2026-10-02"),
        CbrRate(code: "THB", rubPerUnit: 2.47438, date: "2026-10-02"),
    ]

    private let transport: any HTTPTransport
    private let url: URL

    public init(transport: any HTTPTransport = URLSessionTransport(), url: URL = CbrRatesSource.endpoint) {
        self.transport = transport
        self.url = url
    }

    public func fetch() async throws -> [CbrRate] {
        var request = URLRequest(url: url)
        // Both Android timeouts were 10 s. URLRequest has one: it limits how long the connection may
        // stay silent, which covers connecting and waiting for the body.
        request.timeoutInterval = 10
        // The mirror changes once a day, and a cached answer from yesterday defeats the refresh.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw CbrError.http(status: response.statusCode) }
        return try Self.parse(data)
    }

    /// `Date` gives the day (its first 10 characters), `Valute` the rate of each currency: `Value` is the
    /// price of `Nominal` units, so a unit costs `Value / Nominal`. The ruble itself is not listed, so
    /// it is appended at 1.0. Rates come sorted by code, since a JSON object has no order to keep.
    static func parse(_ data: Data) throws -> [CbrRate] {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw CbrError.malformed
        }
        let date = String(payload.date.prefix(10))
        var rates: [CbrRate] = []
        for (code, item) in payload.valute.sorted(by: { $0.key < $1.key }) {
            // Kotlin would divide by a zero nominal and store an infinite rate; refuse the whole answer.
            guard item.nominal > 0, item.value.isFinite else { throw CbrError.malformed }
            rates.append(CbrRate(code: code, rubPerUnit: item.value / item.nominal, date: date))
        }
        rates.append(CbrRate(code: "RUB", rubPerUnit: 1.0, date: date))
        return rates
    }

    private struct Payload: Decodable {
        let date: String
        let valute: [String: Item]

        enum CodingKeys: String, CodingKey {
            case date = "Date"
            case valute = "Valute"
        }
    }

    private struct Item: Decodable {
        let value: Double
        let nominal: Double

        enum CodingKeys: String, CodingKey {
            case value = "Value"
            case nominal = "Nominal"
        }
    }
}
