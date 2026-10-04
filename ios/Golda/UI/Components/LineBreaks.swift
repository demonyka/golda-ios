import Foundation

extension String {
    /// "Карта · ≈ 5 298 117 ₽" as a wrapping line should break it: no-break spaces before each dot,
    /// after each "≈" and after each number, so a wrapped line never starts with a dot, a lone "₽"
    /// or "дней", nor ends with a lone "≈". At the large text sizes the lines under the amounts wrap
    /// often; `Fmt` keeps a plain space before the currency sign, as Android does.
    var keepingMarksOnTheLine: String {
        var glued = ""
        glued.reserveCapacity(count)
        var previous: Character?
        var rest = makeIterator()
        var current = rest.next()
        while let character = current {
            let next = rest.next()
            if character == " ", previous?.isNumber == true, let next, !next.isWhitespace {
                glued.append("\u{00A0}")
            } else {
                glued.append(character)
            }
            previous = character
            current = next
        }
        return glued.replacingOccurrences(of: " · ", with: "\u{00A0}· ").replacingOccurrences(of: "≈ ", with: "≈\u{00A0}")
    }
}
