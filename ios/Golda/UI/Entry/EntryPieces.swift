import GoldaCore
import SwiftUI

// The parts of the operation form, each laid out from values the `EntryFormModel` worked out.

// MARK: - Under the number

/// The one line under the big number: what is safe today, what the card is charged or the other
/// account receives (a glass button that opens the bank's real figure), or what the amount comes
/// to in the other shown currencies.
struct EntryUnderLine: View {
    let line: EntryFormModel.UnderLine
    let secondCode: String?
    @Binding var secondText: String
    @Binding var isEditingSecond: Bool
    var focus: FocusState<EntryFocus?>.Binding

    @Environment(\.locale) private var locale

    var body: some View {
        switch line {
        case .none:
            EmptyView()
        case .safeToday(let amount):
            quiet(EntryText.safeToday(amount, in: locale), spoken: EntryText.safeToday(SpokenAmount.text(amount, locale: locale), in: locale))
        case .others(let text, let approximate):
            let spoken = text.components(separatedBy: " · ").map { SpokenAmount.text($0, locale: locale) }.joined(separator: ", ")
            quiet(approximate ? "≈ " + text : text, spoken: approximate ? EntryText.about(spoken, in: locale) : spoken)
        case .charged(let amount, let isEstimate):
            second(
                EntryText.charged(amount, isEstimate: isEstimate, in: locale),
                spoken: EntryText.charged(amount, isEstimate: isEstimate, in: locale, spoken: true),
                font: .body
            )
        case .received(let amount, let isEstimate):
            second(
                EntryText.received(amount, isEstimate: isEstimate, in: locale),
                spoken: EntryText.received(amount, isEstimate: isEstimate, in: locale, spoken: true),
                font: .title2.weight(.semibold)
            )
        }
    }

    private func quiet(_ text: String, spoken: String) -> some View {
        Text(verbatim: text)
            .font(.body)
            .tabularDigits()
            .foregroundStyle(Theme.Color.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(verbatim: spoken))
            .accessibilityIdentifier("entry.underLine")
    }

    /// The second amount: a glass button, or the field it opens.
    @ViewBuilder private func second(_ text: String, spoken: String, font: Font) -> some View {
        if isEditingSecond, let secondCode {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Gap.s) {
                TextField(text: $secondText, prompt: Text(verbatim: "0")) {
                    Text(verbatim: EntryText.correct.text(in: locale))
                }
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .focused(focus, equals: .second)
                .accessibilityIdentifier("entry.second.field")
                Text(verbatim: Currencies.symbol(secondCode))
                    .foregroundStyle(Theme.Color.muted)
                    .accessibilityHidden(true)
            }
            .font(.title2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, Theme.Gap.m)
            .padding(.vertical, Theme.Gap.s)
            .frame(maxWidth: 240)
            .background(Theme.Color.card, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
            .frame(maxWidth: .infinity)
            .onAppear { focus.wrappedValue = .second }
        } else {
            Button {
                isEditingSecond = true
            } label: {
                HStack(spacing: Theme.Gap.s) {
                    Text(verbatim: text)
                        .font(font)
                        .tabularDigits()
                        .multilineTextAlignment(.center)
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.Color.text)
            }
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(verbatim: spoken))
            .accessibilityHint(Text(verbatim: EntryText.correct.text(in: locale)))
            .accessibilityIdentifier("entry.second")
        }
    }
}

/// Which of the form's SwiftUI fields has the keyboard. The big amount is a UIKit field with a
/// focus flag of its own.
enum EntryFocus: Hashable {
    case note, second
}

// MARK: - Pills

/// "Мультивалютная USD · $ ⌄": the account, rarely changed, as a glass pill with the list.
struct EntryAccountPill: View {
    let accounts: [Account]
    let account: Account?
    var onPick: (UUID) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { account?.id }, set: { if let id = $0 { onPick(id) } })) {
                ForEach(accounts) { account in
                    Label {
                        Text(verbatim: Self.title(account))
                    } icon: {
                        Image(systemName: Symbols.accountType(account.type))
                    }
                    .tag(Optional(account.id))
                }
            } label: {
                Text(verbatim: EntryText.account.text(in: locale))
            }
        } label: {
            EntryPillLabel(
                symbol: account.map { Symbols.accountType($0.type) } ?? Symbols.accountType(.card),
                text: account.map(Self.title) ?? EntryText.account.text(in: locale)
            )
        }
        .buttonStyle(.glass)
        .accessibilityLabel(Text(verbatim: EntryText.account.text(in: locale)))
        .accessibilityValue(Text(verbatim: account?.name ?? ""))
        .accessibilityIdentifier("entry.account")
    }

    static func title(_ account: Account) -> String {
        "\(account.name) · \(Currencies.symbol(account.currency))"
    }
}

/// "Сегодня ⌄": the day, with the calendar in a small sheet of its own. A popover from the pill
/// at the edge of the screen cut the calendar off; a sheet always has room for it.
struct EntryDatePill: View {
    @Binding var date: LocalDate
    let today: LocalDate
    let zone: TimeZone

    @Environment(\.locale) private var locale
    @State private var isPicking = false

    var body: some View {
        Button {
            isPicking = true
        } label: {
            EntryPillLabel(symbol: "calendar", text: DayLabel(date, today: today).text(in: locale))
        }
        .buttonStyle(.glass)
        .accessibilityLabel(Text(verbatim: EntryText.date.text(in: locale)))
        .accessibilityValue(Text(verbatim: DayLabel(date, today: today).text(in: locale)))
        .accessibilityIdentifier("entry.date")
        .sheet(isPresented: $isPicking) {
            NavigationStack {
                ScrollView {
                    DatePicker(selection: day, displayedComponents: .date) {
                        Text(verbatim: EntryText.date.text(in: locale))
                    }
                    .datePickerStyle(.graphical)
                    // Days in the books' zone, the zone a day is turned back with.
                    .environment(\.timeZone, zone)
                    .padding(.horizontal, Theme.Gap.m)
                    .accessibilityIdentifier("entry.datePicker")
                }
                .scrollBounceBehavior(.basedOnSize)
                .navigationTitle(Text(verbatim: EntryText.date.text(in: locale)))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.Color.page)
        }
    }

    /// The day as the picker's midnight in the books' zone, and back; a picked day closes the calendar.
    private var day: Binding<Date> {
        let zone = zone
        return Binding(
            get: { Date(timeIntervalSince1970: Double(date.startOfDayMillis(in: zone)) / 1000) },
            set: {
                let picked = LocalDate(epochMillis: Int64(($0.timeIntervalSince1970 * 1000).rounded(.down)), in: zone)
                if picked != date {
                    date = picked
                    isPicking = false
                }
            }
        )
    }
}

/// A glass pill's inside: a symbol, the text and the menu's chevron.
struct EntryPillLabel: View {
    let symbol: String
    let text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Gap.s) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Color.muted)
            // One line, cut in the middle so the currency at the end stays; at the accessibility
            // sizes the pill has the whole width and the name wraps instead.
            Text(verbatim: text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Color.muted)
        }
        .font(.body)
        .foregroundStyle(Theme.Color.text)
        .frame(minHeight: 32)
    }
}

// MARK: - Categories

/// Every category of the type at once, four across, the most used first. The picked one turns
/// graphite and rounds into a pill, as every pick does in Golda. At the accessibility sizes the
/// names no longer fit four abreast, so the tiles become full-width rows.
struct EntryCategoryGrid: View {
    let categories: [GoldaCore.Category]
    let selected: String?
    var onPick: (String) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let wide = dynamicTypeSize.isAccessibilitySize
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Gap.s), count: wide ? 1 : 4), spacing: Theme.Gap.s) {
            ForEach(categories, id: \.key) { tile($0, wide: wide) }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: EntryText.category.text(in: locale)))
    }

    private func tile(_ category: GoldaCore.Category, wide: Bool) -> some View {
        let picked = category.key == selected
        let name = CategoryName.resource(category.key).text(in: locale)
        return Button {
            onPick(category.key)
        } label: {
            Group {
                if wide {
                    HStack(spacing: Theme.Gap.m) {
                        Image(systemName: Symbols.category(category.key))
                        Text(verbatim: name)
                        Spacer(minLength: 0)
                    }
                    .font(.body)
                    .padding(.horizontal, Theme.Gap.m)
                    .padding(.vertical, Theme.Gap.s)
                } else {
                    VStack(spacing: Theme.Gap.xs) {
                        Image(systemName: Symbols.category(category.key))
                            .font(.title3)
                            .foregroundStyle(picked ? Theme.Color.onGraphite : Theme.Color.muted)
                        Text(verbatim: name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(picked ? Theme.Color.onGraphite : Theme.Color.text)
            // 36 is half the height: the picked tile becomes a pill.
            .background(
                picked ? Theme.Color.graphite : Theme.Color.soft,
                in: RoundedRectangle(cornerRadius: picked ? 36 : 20, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy, value: picked)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("entry.category.\(category.key)")
    }
}

// MARK: - Transfer

/// From and to as two tiles with a round swap button over the gap; a tile opens the list of
/// accounts with their balances. At the accessibility sizes the tiles stack, the button between.
struct EntryRouteTiles: View {
    let form: EntryFormModel
    var onFrom: (UUID) -> Void
    var onTo: (UUID) -> Void
    var onSwap: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Theme.Gap.s)) : AnyLayout(HStackLayout(spacing: Theme.Gap.s))
        // The sides facing the swap button keep clear of it, so it never sits on a name.
        layout {
            tile(EntryText.from, form.account, choices: form.accounts, clear: stacked ? .bottom : .trailing, onPick: onFrom, identifier: "entry.from")
            tile(EntryText.to, form.toAccount, choices: form.destinations, clear: stacked ? .top : .leading, onPick: onTo, identifier: "entry.to")
        }
        .overlay {
            Button(action: onSwap) {
                Image(systemName: dynamicTypeSize.isAccessibilitySize ? "arrow.up.arrow.down" : Symbols.transfer)
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(verbatim: EntryText.swap.text(in: locale)))
            .accessibilityIdentifier("entry.swap")
        }
        .sensoryFeedback(.selection, trigger: form.accountId)
    }

    private func tile(
        _ caption: LocalizedStringResource, _ account: Account?, choices: [Account], clear: Edge.Set,
        onPick: @escaping (UUID) -> Void, identifier: String
    ) -> some View {
        let caption = caption.text(in: locale)
        let balance = account.map(form.balance)
        return Menu {
            Picker(selection: Binding(get: { account?.id }, set: { if let id = $0 { onPick(id) } })) {
                ForEach(choices) { choice in
                    Text(verbatim: "\(choice.name) · \(form.balance(of: choice))").tag(Optional(choice.id))
                }
            } label: {
                Text(verbatim: caption)
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                Text(verbatim: caption)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Color.muted)
                Spacer(minLength: Theme.Gap.s)
                Text(verbatim: account?.name ?? "—")
                    .font(.headline)
                    .foregroundStyle(Theme.Color.text)
                    // One line that shrinks a little before it cuts: two would break a long word.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.7)
                if let balance {
                    Text(verbatim: balance)
                        .font(.subheadline)
                        .tabularDigits()
                        .foregroundStyle(Theme.Color.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(Theme.Gap.m)
            .padding(clear, Theme.Gap.m)
            .background(Theme.Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: caption))
        .accessibilityValue(Text(verbatim: [account?.name, balance.map { SpokenAmount.text($0, locale: locale) }].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - "Сомневаюсь"

/// What the price means, as quiet tiles: hours of work big on the left, the share of the main
/// goal and the days of budget stacked on the right. Dashes until it is known; faded while there
/// is no price. At the accessibility sizes the tiles stack in one column.
struct EntryFactsBento: View {
    let facts: [EntryFormModel.Fact]
    let isPriced: Bool

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var bigSize: CGFloat = 56

    var body: some View {
        if let first = facts.first {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: Theme.Gap.s) {
                        ForEach(facts, id: \.kind) { tile($0, big: $0 == first) }
                    }
                } else {
                    // Two thirds for the big fact, one for the stack beside it, as on Android.
                    ThirdsLayout(spacing: Theme.Gap.s) {
                        tile(first, big: true)
                            .frame(maxHeight: .infinity)
                        if facts.count > 1 {
                            VStack(spacing: Theme.Gap.s) {
                                ForEach(facts.dropFirst(), id: \.kind) { tile($0, big: false).frame(maxHeight: .infinity) }
                            }
                        }
                    }
                    .frame(minHeight: 136)
                }
            }
            .opacity(isPriced ? 1 : 0.6)
        }
    }

    private func tile(_ fact: EntryFormModel.Fact, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(verbatim: fact.value)
                .font(big ? .system(size: min(bigSize, 72), weight: .semibold) : .title2.weight(.semibold))
                .tabularDigits()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: EntryText.factLabel(fact, in: locale))
                .font(big ? .body : .footnote)
                .foregroundStyle(Theme.Color.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
        .foregroundStyle(Theme.Color.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, big ? Theme.Gap.m : 12)
        .padding(.vertical, big ? Theme.Gap.m : Theme.Gap.s)
        .background(Theme.Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: EntryText.spokenFact(fact, in: locale)))
        .accessibilityIdentifier("entry.fact.\(fact.kind)")
    }
}

/// "Не беру · Подумаю · Беру". None of them is the right answer, but buying records the expense,
/// so it is the blue one; "Подумаю" says how long the wait would be. At the accessibility sizes
/// they stack, the blue one at the bottom, nearest the thumb.
struct EntryDecideActions: View {
    let enabled: Bool
    /// "3 дня"; nil while not known.
    let wait: String?
    let withThink: Bool
    var onSkip: () -> Void
    var onThink: () -> Void
    var onBuy: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Gap.s))
            : AnyLayout(HStackLayout(spacing: Theme.Gap.s))
        layout {
            Button(action: onSkip) {
                label(EntryText.skip.text(in: locale), detail: nil)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("entry.skip")
            if withThink {
                Button(action: onThink) {
                    label(EntryText.think.text(in: locale), detail: wait ?? "…")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("entry.think")
            }
            Button(action: onBuy) {
                label(EntryText.buy.text(in: locale), detail: nil)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("entry.buy")
        }
        .controlSize(.large)
        .disabled(!enabled)
        // A bar over the form: past this size the three answers would cover what they answer.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func label(_ title: String, detail: String?) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: title)
                .font(.headline)
            if let detail {
                Text(verbatim: detail)
                    .font(.caption)
                    .tabularDigits()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget)
    }
}

/// Two thirds of the width for the first view and one for the second, both as tall as the taller.
/// With one view it takes the whole width.
struct ThirdsLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let height = widths(width, subviews.count).enumerated().map { index, part in
            subviews[index].sizeThatFits(ProposedViewSize(width: part, height: proposal.height)).height
        }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (index, part) in widths(bounds.width, subviews.count).enumerated() {
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: part, height: bounds.height)
            )
            x += part + spacing
        }
    }

    private func widths(_ total: CGFloat, _ count: Int) -> [CGFloat] {
        guard count > 1 else { return count == 1 ? [total] : [] }
        let share = (total - spacing) / 3
        return [share * 2, share]
    }
}
