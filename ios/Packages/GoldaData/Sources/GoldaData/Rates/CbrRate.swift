import Foundation

/// One official rate: how many rubles a single unit of [code] costs on [date].
public struct CbrRate: Hashable, Sendable, Codable {
    public var code: String
    public var rubPerUnit: Double
    /// `yyyy-MM-dd`, as the Bank of Russia dates the rates. A string on purpose: the table keeps
    /// it verbatim and nothing computes with it.
    public var date: String

    public init(code: String, rubPerUnit: Double, date: String) {
        self.code = code
        self.rubPerUnit = rubPerUnit
        self.date = date
    }
}

/// Where fresh rates come from. The app asks, and the database stores what comes back.
public protocol RatesSource: Sendable {
    func fetch() async throws -> [CbrRate]
}
