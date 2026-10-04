import Foundation
import GoldaCore

public enum CurrencyApiError: Error, Equatable, Sendable {
    /// The server answered with a status outside 2xx.
    case http(status: Int)
    /// The answer was not the JSON we expect: broken text, or no day or no table of rates.
    case malformed
}

/// Market rates for the currencies the Bank of Russia does not publish (the Argentine peso, the
/// Mexican peso…), from Fawaz Ahmed's free currency API: no key, CC0, refreshed daily. Not in
/// Android, which knew only the CBR. `MergedRatesSource` takes from here only what the CBR lacks.
public struct CurrencyApiRatesSource: RatesSource {
    /// The CDN first, then the API's own mirror on Cloudflare Pages, as its README advises.
    public static let endpoints = [
        URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/rub.json")!,
        URL(string: "https://latest.currency-api.pages.dev/v1/currencies/rub.json")!,
    ]

    private let transport: any HTTPTransport
    private let urls: [URL]

    public init(transport: any HTTPTransport = URLSessionTransport(), urls: [URL] = CurrencyApiRatesSource.endpoints) {
        self.transport = transport
        self.urls = urls
    }

    /// The first address that gives a readable answer; the error of the last one when none does.
    public func fetch() async throws -> [CbrRate] {
        var failure: any Error = URLError(.badURL)
        for url in urls {
            do {
                return try await fetch(url)
            } catch {
                failure = error
            }
        }
        throw failure
    }

    private func fetch(_ url: URL) async throws -> [CbrRate] {
        var request = URLRequest(url: url)
        // As for the CBR: ten seconds of silence is a failure, and yesterday's cached file is no refresh.
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw CurrencyApiError.http(status: response.statusCode) }
        return try Self.parse(data)
    }

    /// `date` is the day, `rub` how many units of each currency a ruble buys, under lowercase codes,
    /// so a unit costs `1 / value` rubles. Only the catalogue's currencies are kept: the table also
    /// lists crypto tokens, metals and long-gone currencies. A value that is not a positive number
    /// drops that currency alone, since one odd token among hundreds must not cost the peso its rate.
    /// The ruble is left out: the CBR's 1.0 is the one.
    static func parse(_ data: Data) throws -> [CbrRate] {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw CurrencyApiError.malformed
        }
        let wanted = Set(Currencies.all).subtracting(["RUB"])
        return payload.rub
            .compactMap { key, value -> CbrRate? in
                let code = key.uppercased()
                guard wanted.contains(code), let perRub = value.number, perRub > 0, perRub.isFinite else { return nil }
                let rubPerUnit = 1 / perRub
                return rubPerUnit.isFinite ? CbrRate(code: code, rubPerUnit: rubPerUnit, date: payload.date) : nil
            }
            .sorted { $0.code < $1.code }
    }

    private struct Payload: Decodable {
        let date: String
        let rub: [String: Value]
    }

    /// A number, or nil for anything else, so a stray string or null skips one entry.
    private struct Value: Decodable {
        let number: Double?

        init(from decoder: any Decoder) throws {
            number = try? decoder.singleValueContainer().decode(Double.self)
        }
    }
}

/// The Bank of Russia's rates with the gaps filled from a second source. The CBR stays the source
/// of every currency it publishes, and its failure is the refresh's failure, as before; the second
/// source's failure only means the gaps keep the rates they had (or stay without one, which the
/// app handles as any missing rate: amounts stay in rubles and wait for a rate).
public struct MergedRatesSource: RatesSource {
    private let official: any RatesSource
    private let supplement: any RatesSource

    public init(official: any RatesSource, supplement: any RatesSource) {
        self.official = official
        self.supplement = supplement
    }

    /// The live pair: the CBR mirror and the currency API.
    public static func live(transport: any HTTPTransport = URLSessionTransport()) -> MergedRatesSource {
        MergedRatesSource(official: CbrRatesSource(transport: transport), supplement: CurrencyApiRatesSource(transport: transport))
    }

    public func fetch() async throws -> [CbrRate] {
        // Both at once: each may wait its ten seconds.
        async let filler = try? supplement.fetch()
        let rates = try await official.fetch()
        guard let extra = await filler else { return rates }
        let published = Set(rates.map(\.code))
        // The table keeps one day per refresh, the CBR's: Settings names the newest day as the
        // Bank of Russia's ("ЦБ на 3 октября"), and the second source's own is a day off at most.
        let day = rates.first { $0.code == "RUB" }?.date ?? rates.map(\.date).max()
        return rates + extra
            .filter { !published.contains($0.code) }
            .map { CbrRate(code: $0.code, rubPerUnit: $0.rubPerUnit, date: day ?? $0.date) }
    }
}
