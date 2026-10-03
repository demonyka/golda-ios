import Foundation
import GoldaCore
import SwiftUI

/// A day's heading over its operations: "Today", "Yesterday", "30 September".
enum DayLabel: Equatable, Sendable {
    case today
    case yesterday
    case date(LocalDate)

    init(_ date: LocalDate, today: LocalDate) {
        switch date {
        case today: self = .today
        case today.minusDays(1): self = .yesterday
        default: self = .date(date)
        }
    }

    /// "Сегодня", "Вчера", "30 сентября" in Russian; "Today", "Yesterday", "September 30" in English.
    func text(in locale: Locale) -> String {
        switch self {
        case .today: LocalizedStringResource("Today", comment: "Heading of today's operations.").text(in: locale)
        case .yesterday: LocalizedStringResource("Yesterday", comment: "Heading of yesterday's operations.").text(in: locale)
        case .date(let date): Self.dayAndMonth(date, locale: locale)
        }
    }

    /// The day and the month's name the way [locale] writes them together: "d MMMM" in Russian (the
    /// month in the genitive), "MMMM d" in English, as Android's patterns.
    private static func dayAndMonth(_ date: LocalDate, locale: Locale) -> String {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let instant = Date(timeIntervalSince1970: Double(date.epochDay) * 86_400 + 12 * 3_600)
        return instant.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: utc).day().month(.wide))
    }
}

/// One day of operations, newest first, under its heading.
struct OperationDay: Identifiable, Equatable, Sendable {
    let date: LocalDate
    let label: DayLabel
    let rows: [OperationRowModel]

    var id: LocalDate { date }

    /// [operations] (newest first) by the day they happened in [zone], in the order the days first
    /// appear, as Kotlin's `groupBy` keeps them. On an account's page pass [accountId], so each row
    /// shows that account's own side.
    static func group(_ operations: [OperationFull], in data: AppData, today: LocalDate, accountId: UUID? = nil) -> [OperationDay] {
        var order: [LocalDate] = []
        var byDay: [LocalDate: [OperationRowModel]] = [:]
        for full in operations {
            guard let row = OperationRowModel(full, in: data, accountId: accountId) else { continue }
            let day = Ledger.localDate(full.op.timestamp, data.zone)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(row)
        }
        return order.map { OperationDay(date: $0, label: DayLabel($0, today: today), rows: byDay[$0] ?? []) }
    }
}

/// Operations by day as sections of an inset-grouped list, each day under its heading and each row
/// a button that hands its operation on. Home and an account's page put it under their hero.
struct OperationDaySections: View {
    let days: [OperationDay]
    /// What UI tests find the rows by: "home.operation", "account.operation".
    let rowIdentifier: String
    var onSelect: (OperationFull) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        ForEach(days) { day in
            Section {
                ForEach(day.rows) { row in
                    Button {
                        onSelect(row.operation)
                    } label: {
                        OperationRowView(row: row)
                    }
                    .listRowBackground(Theme.Color.card)
                    .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
                    .accessibilityIdentifier(rowIdentifier)
                }
            } header: {
                Text(verbatim: day.label.text(in: locale))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Color.muted)
                    .textCase(nil)
            }
        }
    }
}
