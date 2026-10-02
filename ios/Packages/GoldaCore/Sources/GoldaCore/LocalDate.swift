import Foundation

/// Calendar dates without a time zone or time of day: the mirror of `java.time.LocalDate` and
/// `YearMonth` that the Kotlin logic is written against. Instants stay `Int64` epoch milliseconds,
/// and a zone is passed in wherever a day boundary matters.
public enum DayOfWeek: Int, Sendable, CaseIterable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public var isWeekend: Bool { self == .saturday || self == .sunday }

    /// Lower-case nominative, as `getDisplayName(FULL, ru)` gives it.
    public var russianName: String {
        ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"][rawValue - 1]
    }
}

public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let epochDay: Int

    public init(epochDay: Int) {
        self.epochDay = epochDay
    }

    /// A valid date is expected, as `LocalDate.of` expects one.
    public init(_ year: Int, _ month: Int, _ day: Int) {
        precondition((1...12).contains(month) && (1...Self.monthLength(year, month)).contains(day), "Invalid date \(year)-\(month)-\(day)")
        self.epochDay = Self.daysFromCivil(year, month, day)
    }

    /// Strict `yyyy-MM-dd`, like `LocalDate.parse`; nil for anything else.
    public init?(iso text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              text.allSatisfy({ $0 == "-" || ("0"..."9").contains($0) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...Self.monthLength(y, m)).contains(d)
        else { return nil }
        self.init(y, m, d)
    }

    /// The day an instant falls on in [zone].
    public init(epochMillis: Int64, in zone: TimeZone) {
        let date = Date(timeIntervalSince1970: Double(epochMillis) / 1000)
        let local = Self.floorDiv(epochMillis, 1000) + Int64(zone.secondsFromGMT(for: date))
        self.epochDay = Int(Self.floorDiv(local, 86_400))
    }

    public var year: Int { Self.civil(epochDay).year }
    public var month: Int { Self.civil(epochDay).month }
    public var day: Int { Self.civil(epochDay).day }

    public var dayOfWeek: DayOfWeek {
        // 1970-01-01 was a Thursday.
        DayOfWeek(rawValue: ((epochDay % 7) + 7 + 3) % 7 + 1)!
    }

    public var lengthOfMonth: Int { Self.monthLength(year, month) }

    public func plusDays(_ n: Int) -> LocalDate { LocalDate(epochDay: epochDay + n) }

    public func minusDays(_ n: Int) -> LocalDate { plusDays(-n) }

    /// The day of month is clamped to the target month's length, as `java.time` does.
    public func plusMonths(_ n: Int) -> LocalDate {
        let c = Self.civil(epochDay)
        let total = c.year * 12 + (c.month - 1) + n
        let y = Int(Self.floorDiv(Int64(total), 12))
        let m = Int(Self.floorMod(Int64(total), 12)) + 1
        return LocalDate(y, m, min(c.day, Self.monthLength(y, m)))
    }

    public func minusMonths(_ n: Int) -> LocalDate { plusMonths(-n) }

    public func withDayOfMonth(_ day: Int) -> LocalDate { LocalDate(year, month, day) }

    public func isBefore(_ other: LocalDate) -> Bool { self < other }

    public func isAfter(_ other: LocalDate) -> Bool { self > other }

    /// Whole days from [from] to [to], negative when [to] is earlier.
    public static func daysBetween(_ from: LocalDate, _ to: LocalDate) -> Int { to.epochDay - from.epochDay }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.epochDay < rhs.epochDay }

    public var description: String {
        let c = Self.civil(epochDay)
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    // MARK: Instants

    /// Midnight at the start of this day in [zone], as epoch milliseconds.
    public func startOfDayMillis(in zone: TimeZone) -> Int64 { atTimeMillis(hour: 0, minute: 0, in: zone) }

    public func atTimeMillis(hour: Int, minute: Int = 0, in zone: TimeZone) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        let date = calendar.date(from: parts) ?? Date(timeIntervalSince1970: Double(epochDay) * 86_400)
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: Civil calendar (Howard Hinnant's algorithms)

    static func isLeap(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    static func monthLength(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(_ epochDay: Int) -> (year: Int, month: Int, day: Int) {
        let z = epochDay + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400
        return (month <= 2 ? year + 1 : year, month, day)
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func floorMod(_ a: Int64, _ b: Int64) -> Int64 { a - floorDiv(a, b) * b }
}

public struct YearMonth: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int

    public init(_ year: Int, _ month: Int) {
        precondition((1...12).contains(month), "Invalid month \(month)")
        self.year = year
        self.month = month
    }

    public init(from date: LocalDate) {
        self.init(date.year, date.month)
    }

    public var lengthOfMonth: Int { LocalDate.monthLength(year, month) }

    public func atDay(_ day: Int) -> LocalDate { LocalDate(year, month, day) }

    public func plusMonths(_ n: Int) -> YearMonth {
        let total = year * 12 + (month - 1) + n
        return YearMonth(Int(LocalDate.floorDiv(Int64(total), 12)), Int(LocalDate.floorMod(Int64(total), 12)) + 1)
    }

    public func minusMonths(_ n: Int) -> YearMonth { plusMonths(-n) }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}
