import Foundation
import Testing

@testable import Golda

/// Every String Catalog of the app carries each line in Russian and in English, and the catalogs and
/// the code agree: each key the code asks for by its literal is in its table, and each key of a table
/// is asked for (CLAUDE.md: every line in both languages, in one change).
///
/// The build extracts nothing from the code: it compiles only what the catalogs hold. A key the code
/// asks for and a catalog lacks would show its English key to a Russian reader, with no warning; a key
/// no code asks for is a leftover of a screen that changed. So this reads the catalogs and the sources
/// themselves, from the repository this file is in (the simulator sees the Mac's disk).
@Suite struct StringCatalogTests {
    /// `ios/`, two folders above this file.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let resources = root.appending(path: "Golda/Resources", directoryHint: .isDirectory)
    /// The app's and the widgets', which share the `EntryPoints` table.
    private static let sources = ["Golda", "GoldaWidgets"].map { root.appending(path: $0, directoryHint: .isDirectory) }

    /// Each table's keys with what the catalog says about them, by table name ("Localizable", "Entry").
    private static func catalogs() throws -> [String: [String: [String: Any]]] {
        let files = try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xcstrings" }
        var result: [String: [String: [String: Any]]] = [:]
        for file in files {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            result[file.deletingPathExtension().lastPathComponent] = json?["strings"] as? [String: [String: Any]] ?? [:]
        }
        return result
    }

    @Test func theCatalogsAreThere() throws {
        let tables = Set(try Self.catalogs().keys)
        #expect(tables.isSuperset(of: ["Localizable", "InfoPlist", "Components", "Entry", "Goals", "Insights", "Profiles", "Settings", "Voice", "AccountForm", "Failure", "Onboarding", "EntryPoints", "AppShortcuts"]), "\(tables)")
    }

    // MARK: Both languages

    /// The plural forms each language needs: Russian tells one, few and many apart.
    private static let pluralForms = ["en": ["one", "other"], "ru": ["one", "few", "many", "other"]]

    @Test func everyLineIsInRussianAndInEnglish() throws {
        var problems: [String] = []
        for (table, strings) in try Self.catalogs() {
            for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false {
                let localizations = entry["localizations"] as? [String: Any] ?? [:]
                for language in ["en", "ru"] {
                    let place = "\(table) “\(key)” \(language)"
                    guard let localization = localizations[language] as? [String: Any] else {
                        problems.append("\(place): missing")
                        continue
                    }
                    if let unit = localization["stringUnit"] as? [String: Any] {
                        problems += Self.check(unit, at: place)
                    } else if let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                        for form in Self.pluralForms[language] ?? [] {
                            guard let unit = (plural[form] as? [String: Any])?["stringUnit"] as? [String: Any] else {
                                problems.append("\(place): no plural form “\(form)”")
                                continue
                            }
                            problems += Self.check(unit, at: "\(place) \(form)")
                        }
                    } else {
                        problems.append("\(place): neither a line nor plural forms")
                    }
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.sorted().joined(separator: "\n"))")
    }

    private static func check(_ unit: [String: Any], at place: String) -> [String] {
        var problems: [String] = []
        if unit["state"] as? String != "translated" { problems.append("\(place): state \(unit["state"] ?? "none")") }
        if (unit["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("\(place): empty") }
        return problems
    }

    // MARK: Catalogs and code agree

    @Test func everyKeyTheCodeAsksForIsInItsTable() throws {
        let catalogs = try Self.catalogs()
        var problems: [String] = []
        for use in try Self.uses() {
            guard let strings = catalogs[use.table] else {
                problems.append("\(use.file): no table \(use.table) for “\(use.key)”")
                continue
            }
            if !strings.keys.contains(where: { Self.matches($0, use.key) }) {
                problems.append("\(use.file): “\(use.key)” is not in \(use.table)")
            }
        }
        #expect(problems.isEmpty, "\(problems.sorted().joined(separator: "\n"))")
    }

    @Test func everyKeyOfATableIsAskedFor() throws {
        let uses = try Self.uses()
        var problems: [String] = []
        // The plist's keys are Info.plist keys, read by the system; Siri reads the phrases of
        // `GoldaShortcuts` from AppShortcuts, which no call asks for.
        for (table, strings) in try Self.catalogs() where table != "InfoPlist" && table != "AppShortcuts" {
            let asked = uses.filter { $0.table == table }.map(\.key)
            for key in strings.keys where !asked.contains(where: { Self.matches(key, $0) }) {
                problems.append("\(table): “\(key)” is never asked for")
            }
        }
        #expect(problems.isEmpty, "\(problems.sorted().joined(separator: "\n"))")
    }

    /// The scanner itself: the call shapes it reads, interpolations and escapes.
    @Test func theScannerReadsTheCallShapesTheAppUses() {
        let source = #"""
        static let a = LocalizedStringResource("Done", table: "Settings", comment: "x")
        static let b = LocalizedStringResource(
            "\(count) days of budget", table: "Entry",
            comment: "Shown as “3 days”.")
        Text("Profile: \(name)")
        Text(verbatim: "Golda")
        Text("Cancel", tableName: "Profiles", comment: "y")
        Button("New profile", systemImage: "plus") {}
        static let c = LocalizedStringResource("Save.new", defaultValue: "Save", table: "Entry")
        String(localized: "Undo", table: "Components")
        static let d = resource("Main currency", "z")
        static func e(_ day: String) -> LocalizedStringResource { LocalizedStringResource("CBR of \(day)", table: table) }
        /// `Button("Settings") { … }` in a comment asks for nothing.
        private static let table = "Settings"
        """#
        let found = Self.uses(in: source, file: "x.swift").map { "\($0.table)/\($0.key)" }
        #expect(found == [
            "Settings/Done", "Entry/\u{1} days of budget", "Localizable/Profile: \u{1}", "Profiles/Cancel", "Localizable/New profile",
            "Entry/Save.new", "Components/Undo", "Settings/Main currency", "Settings/CBR of \u{1}",
        ])
        #expect(Self.matches("%lld days of budget", "\u{1} days of budget"))
        #expect(Self.matches("“%@” deleted", "“\u{1}” deleted"))
        #expect(!Self.matches("%@ deleted", "Deleted"))
    }

    // MARK: Reading the code

    private struct Use: Hashable {
        let table: String
        /// The key with each interpolation as `\u{1}`.
        let key: String
        let file: String
    }

    /// Every localized line the app's sources ask for by a literal key, and the tab titles, which
    /// are bare literals typed as `LocalizedStringResource`.
    private static func uses() throws -> [Use] {
        let files = sources.flatMap { folder in
            FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
        }
        var result: [Use] = []
        for file in files {
            result += uses(in: try String(contentsOf: file, encoding: .utf8), file: file.lastPathComponent)
        }
        result += AppTab.allCases.map { Use(table: $0.title.table ?? "Localizable", key: $0.title.key, file: "MainTabs.swift") }
        return result
    }

    /// The calls that take a localized key first; `resource(` is a file's own helper over its table.
    private static let calls = [
        "LocalizedStringResource(", "String(localized:", "Text(", "Button(", "TextField(", "SecureField(", "Picker(",
        "Toggle(", "Label(", "Section(", ".alert(", ".navigationTitle(", ".confirmationDialog(", "resource(",
    ]

    private static func uses(in source: String, file: String) -> [Use] {
        // Comment lines show calls as examples (`Button("Settings") { … }`); they ask for nothing.
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let text = Array(code.unicodeScalars)
        let ownTable = firstMatch(of: #/static let table = "(\w+)"/#, in: source)
        var result: [Use] = []
        var index = 0
        while index < text.count {
            guard let call = calls.first(where: { matchesCall($0, in: text, at: index) }) else {
                index += 1
                continue
            }
            var cursor = index + call.unicodeScalars.count
            // `String(localized: "…"`: the label is part of the call's name above.
            while cursor < text.count, text[cursor].properties.isWhitespace { cursor += 1 }
            guard cursor < text.count, text[cursor] == "\"", !(cursor + 2 < text.count && text[cursor + 1] == "\"" && text[cursor + 2] == "\"") else {
                index += 1
                continue
            }
            let (key, afterLiteral) = readLiteral(text, from: cursor)
            let end = endOfCall(text, from: afterLiteral)
            let arguments = String(String.UnicodeScalarView(text[afterLiteral..<end]))
            let table: String
            if call == "resource(" {
                guard let ownTable else {
                    index = afterLiteral
                    continue
                }
                table = ownTable
            } else if let named = firstMatch(of: #/(?:table|tableName):\s*"(\w+)"/#, in: arguments) {
                table = named
            } else if let ownTable, arguments.contains(#/(?:table|tableName):\s*table\b/#) {
                // `table: table`, the file's own constant.
                table = ownTable
            } else {
                table = "Localizable"
            }
            result.append(Use(table: table, key: key, file: file))
            index = afterLiteral
        }
        return result
    }

    /// [call] starts at [index], and is not the tail of a longer name (`MyText(`).
    private static func matchesCall(_ call: String, in text: [Unicode.Scalar], at index: Int) -> Bool {
        let scalars = Array(call.unicodeScalars)
        guard index + scalars.count <= text.count, Array(text[index..<index + scalars.count]) == scalars else { return false }
        if scalars.first == ".", index > 0 { return true }
        guard index > 0 else { return true }
        let before = text[index - 1]
        return !(before.properties.isAlphabetic || before.properties.numericType != nil || before == "_" || before == ".")
    }

    /// The string literal opening at [start], with escapes resolved and each `\(…)` as `\u{1}`, and
    /// the index after its closing quote.
    private static func readLiteral(_ text: [Unicode.Scalar], from start: Int) -> (String, Int) {
        var key = String.UnicodeScalarView()
        var index = start + 1
        while index < text.count, text[index] != "\"" {
            guard text[index] == "\\", index + 1 < text.count else {
                key.append(text[index])
                index += 1
                continue
            }
            let escaped = text[index + 1]
            switch escaped {
            case "(":
                // Up to the parenthesis that closes the interpolation, over nested ones and literals.
                index = endOfCall(text, from: index + 2)
                key.append("\u{1}")
                continue
            case "n": key.append("\n")
            case "t": key.append("\t")
            case "u":
                let digits = text[(index + 3)...].prefix { $0 != "}" }
                if let value = UInt32(String(String.UnicodeScalarView(digits)), radix: 16), let scalar = Unicode.Scalar(value) {
                    key.append(scalar)
                }
                index += 3 + digits.count + 1
                continue
            default: key.append(escaped)
            }
            index += 2
        }
        return (String(key), index + 1)
    }

    /// The index after the parenthesis that closes a call whose opening one is already behind
    /// [start], stepping over string literals.
    private static func endOfCall(_ text: [Unicode.Scalar], from start: Int) -> Int {
        var depth = 1
        var index = start
        while index < text.count, depth > 0 {
            switch text[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case "\"": index = readLiteral(text, from: index).1 - 1
            default: break
            }
            index += 1
        }
        return index
    }

    private static func firstMatch(of regex: Regex<(Substring, Substring)>, in text: String) -> String? {
        text.firstMatch(of: regex).map { String($0.output.1) }
    }

    /// A catalog key and a key read from the code are the same line: the catalog's format
    /// specifiers stand where the code interpolates, and "%%" is a written percent sign.
    private static func matches(_ catalogKey: String, _ codeKey: String) -> Bool {
        let specifier = #/%(?:\d+\$)?(?:lld|llu|ld|lu|d|i|u|@|lf|f|\.\d+f)/#
        let normalized = catalogKey.replacing(specifier, with: "\u{1}").replacingOccurrences(of: "%%", with: "%")
        return normalized == codeKey.replacingOccurrences(of: "%%", with: "%")
    }
}
