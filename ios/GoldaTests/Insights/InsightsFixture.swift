import Foundation
import GoldaCore
import GoldaData

@testable import Golda

/// `AnalyticsTest.kt`'s books on `HomeFixture`'s profile ("today" is 2026-10-02, a Friday, payday the
/// 10th, rubles the main currency): the week holds 500 ₽ eating out, 10 $ of groceries that cost
/// 920 ₽, another 300 ₽ eating out yesterday, 1 000 ₽ of income, and 46 000 ₽ changed into 500 $
/// while the CBR said 83,2454 (4 377,30 ₽ lost on the way). 9 999 ₽ eating out on September 20 is
/// outside the week and inside the month.
struct InsightsFixture {
    typealias F = HomeFixture

    static let today = F.today

    var home = HomeFixture()

    init(operations: [OperationFull]? = nil) {
        home.operations = operations ?? Self.week(home)
    }

    var data: AppData { home.data }

    func content(_ kind: PeriodKind = .week, custom: Period? = nil, data: AppData? = nil) -> InsightsContent {
        InsightsContent(data: data ?? self.data, today: Self.today, kind: kind, custom: custom)
    }

    /// A day of this book at noon, in UTC.
    static func at(_ day: Int, month: Int = 10, hour: Int = 12) -> Int64 {
        F.at(LocalDate(2026, month, day), hour: hour)
    }

    /// An expense of [rub] kopecks from the ruble card.
    static func expense(_ home: HomeFixture, _ category: String?, rub: Int64, day: Int = 2, month: Int = 10, hour: Int = 12) -> OperationFull {
        F.operation(.expense, at: at(day, month: month, hour: hour), category: category, [(home.rub, -rub, -rub)])
    }

    /// The week as the Kotlin test has it, newest first.
    static func week(_ home: HomeFixture) -> [OperationFull] {
        let exchange = Operation(type: .transfer, timestamp: at(1), cbrFrom: 1.0, cbrTo: 83.2454)
        return [
            F.operation(.expense, at: at(2, hour: 13), category: "groceries", [(home.usd, -1_000, -92_000)]),
            expense(home, "eating_out", rub: 50_000, hour: 9),
            expense(home, "eating_out", rub: 30_000, day: 1),
            F.operation(.income, at: at(1), [(home.rub, 100_000, 100_000)]),
            OperationFull(exchange, [
                Posting(operationId: exchange.id, accountId: home.rub.id, amountMinor: -4_600_000, rubMinor: -4_600_000),
                Posting(operationId: exchange.id, accountId: home.usd.id, amountMinor: 50_000, rubMinor: 4_600_000),
            ]),
            expense(home, "eating_out", rub: 999_900, day: 20, month: 9),
        ]
    }
}
