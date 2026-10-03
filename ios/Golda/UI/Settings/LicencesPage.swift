import SwiftUI

/// The licences Golda for iOS ships under (the MIT licence of the original asks for its notice in
/// every copy): who made what, in the interface's language, and each licence as written, in
/// English, since only that text is the licence. No links: the page says it all.
struct LicencesPage: View {
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            ForEach(Licence.all) { licence in
                Section {
                    VStack(alignment: .leading, spacing: Theme.Gap.s) {
                        Text(verbatim: licence.credit.text(in: locale))
                            .foregroundStyle(Theme.Color.text)
                        Text(verbatim: licence.text)
                            .font(.footnote)
                            .foregroundStyle(Theme.Color.muted)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, Theme.Gap.xs)
                } header: {
                    Text(verbatim: licence.name)
                }
                .listRowBackground(Theme.Color.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        .navigationTitle(Text(verbatim: SettingsText.licences.text(in: locale)))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.licences")
    }
}

/// A work Golda for iOS is made of or with, and its licence.
struct Licence: Identifiable, Sendable {
    let name: String
    let credit: LocalizedStringResource
    /// The copyright line and the licence, verbatim.
    let text: String

    var id: String { name }

    static let all = [
        Licence(name: "Golda", credit: SettingsText.goldaCredit, text: "MIT License\n\nCopyright (c) 2026 Shamil Aminov\n\n" + mit),
        Licence(name: "GRDB.swift", credit: SettingsText.grdbCredit, text: "Copyright (C) 2015-2025 Gwendal Roué\n\n" + mit),
        Licence(name: "Tailwind CSS", credit: SettingsText.tailwindCredit, text: "MIT License\n\nCopyright (c) Tailwind Labs, Inc.\n\n" + mit),
    ]

    /// The body of the MIT licence, the same in all three.
    private static let mit = """
        Permission is hereby granted, free of charge, to any person obtaining a copy of this software \
        and associated documentation files (the "Software"), to deal in the Software without \
        restriction, including without limitation the rights to use, copy, modify, merge, publish, \
        distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the \
        Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or \
        substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING \
        BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND \
        NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, \
        DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
}
