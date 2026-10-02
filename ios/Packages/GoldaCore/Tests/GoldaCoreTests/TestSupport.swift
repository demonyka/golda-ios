import Foundation
import Testing

@testable import GoldaCore

/// A stable id for fixture number [n]; the Kotlin tests used the Long ids 1, 2, 3.
func uid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
}

let utc = TimeZone(secondsFromGMT: 0)!

func expectClose(_ actual: Double, _ expected: Double, _ tolerance: Double, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(actual - expected) <= tolerance, "\(actual) is not within \(tolerance) of \(expected)", sourceLocation: sourceLocation)
}

/// The last word of each " · "-separated part: the currency symbols of an "others" line.
func symbols(of line: String) -> [String] {
    line.components(separatedBy: " · ").map { String($0.split(separator: " ").last ?? "") }
}
