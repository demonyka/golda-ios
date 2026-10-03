import GoldaCore
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.f4studio.golda", category: "Goals")

/// "Копилка", in Accounts' grammar: the main goal is the hero (what is saved, the wavy bar, how far
/// along, what refusals put in), then the other goals ending in "+ Цель", the wishes waiting for a
/// decision, and what was decided, folded away. The port of Android's `GoalsScreen`.
///
/// A goal opens its form; a waiting wish opens "Сомневаюсь" through the router; wishes leave with a
/// swipe or a long press and come back with "Отменить".
struct GoalsScreen: View {
    let data: AppData

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.locale) private var locale
    @Environment(\.showUndoToast) private var showUndoToast
    @State private var goalForm: GoalFormRequest?
    @State private var purchase: GoalPurchasePlan?
    @State private var showsDecided: Bool
    @State private var failure: String?

    /// [showsDecided] opens "Решено" from the start, for previews and pictures.
    init(data: AppData, showsDecided: Bool = false) {
        self.data = data
        _showsDecided = State(initialValue: showsDecided)
    }

    /// The goal form over the tab: empty from "+ Цель", or for a goal from its row or the hero.
    private struct GoalFormRequest: Identifiable {
        let goal: Goal?
        let id = UUID()
    }

    var body: some View {
        let content = GoalsContent(data: data, now: model.environment.clock(), celebratedGoalId: model.celebratedGoalId)
        List {
            Section {
                GoalsHeroView(
                    hero: content.hero,
                    onOpen: { goalForm = GoalFormRequest(goal: mainGoal(content)) },
                    onBuy: { purchase = GoalPurchasePlan(goal: $0, data: data, now: model.environment.clock()) },
                    onCelebrated: { model.markGoalCelebrated($0) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            goalsSection(content)
            waitingSection(content)
            decidedSection(content)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        .animation(.snappy, value: content.goals)
        .animation(.snappy, value: content.waiting.map(\.id))
        .animation(.snappy, value: content.decided.map(\.id))
        .sheet(item: $goalForm) { request in
            GoalFormSheet(
                data: data, editing: request.goal,
                onDismiss: { goalForm = nil },
                onDelete: { goal in
                    goalForm = nil
                    delete(goal)
                }
            )
        }
        .alert(
            Text(verbatim: purchase?.title(in: locale) ?? ""),
            isPresented: Binding(get: { purchase != nil }, set: { if !$0 { purchase = nil } }),
            presenting: purchase
        ) { plan in
            if plan.canBuy {
                Button(role: .cancel) {} label: { Text(verbatim: GoalFormModel.cancelTitle.text(in: locale)) }
                // The confirm role and the default shortcut make it the alert's preferred button,
                // filled with the system blue (D34).
                Button(role: .confirm) { buy(plan.goal) } label: { Text(verbatim: GoalPurchasePlan.buyTitle.text(in: locale)) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(role: .cancel) {} label: { Text(verbatim: GoalFormModel.okTitle.text(in: locale)) }
            }
        } message: { plan in
            Text(verbatim: plan.message(in: locale))
        }
        .alert(
            Text(verbatim: failure ?? ""),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button(role: .cancel) {} label: { Text(verbatim: GoalFormModel.okTitle.text(in: locale)) }
        }
    }

    private func mainGoal(_ content: GoalsContent) -> Goal? {
        if case .main(let hero) = content.hero { return hero.goal }
        return nil
    }

    // MARK: Sections

    /// The goals other than the main one, and "+ Цель" closing them. With no goal at all the row is
    /// there too, next to the hero that asks for one: a plain tile alone does not read as a button.
    @ViewBuilder private func goalsSection(_ content: GoalsContent) -> some View {
        Section {
            ForEach(content.goals) { row in
                Button { goalForm = GoalFormRequest(goal: row.goal) } label: {
                    GoalRowView(row: row)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.Color.card)
                .accessibilityIdentifier("goals.goal")
            }
            addRow
        } header: {
            if let header = content.goalsHeader {
                sectionHeader(header.text(in: locale))
            }
        }
    }

    /// "+ Цель" in the system blue, as an action row of an iOS list reads (D34).
    private var addRow: some View {
        Button { goalForm = GoalFormRequest(goal: nil) } label: {
            HStack(spacing: Theme.Gap.m) {
                Image(systemName: Symbols.add)
                Text(verbatim: GoalsContent.addTitle.text(in: locale))
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityLabel(Text(verbatim: GoalsContent.addLabel.text(in: locale)))
        .accessibilityIdentifier("goals.add")
    }

    @ViewBuilder private func waitingSection(_ content: GoalsContent) -> some View {
        if !content.waiting.isEmpty {
            Section {
                ForEach(content.waiting) { row in
                    // A waiting wish opens "Сомневаюсь" without "Подумаю": it has been thought about.
                    Button {
                        router.present(.entry(EntryRequest(consider: row.consider, wishId: row.wish.id)))
                    } label: {
                        WishRowView(title: row.wish.title, detail: row.detailText(in: locale), amount: row.amount)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.Color.card)
                    .accessibilityHint(Text(verbatim: GoalsContent.wishHint.text(in: locale)))
                    .accessibilityIdentifier("goals.wish")
                    .modifier(RemovableWish(title: removeTitle) { remove(row.wish) })
                }
            } header: {
                sectionHeader(GoalsContent.waitingTitle.text(in: locale))
            }
        }
    }

    /// "Решено · N", folded until tapped; the newest 30 under it.
    @ViewBuilder private func decidedSection(_ content: GoalsContent) -> some View {
        if content.decidedCount > 0 {
            Section {
                // The system's disclosure row: its chevron in the tint says it opens, and VoiceOver
                // says whether it is open.
                DisclosureGroup(isExpanded: $showsDecided) {
                    ForEach(content.decided) { row in
                        WishRowView(title: row.wish.title, detail: row.detailText(in: locale), amount: row.amount)
                            .listRowBackground(Theme.Color.card)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
                            .accessibilityIdentifier("goals.decided")
                            .modifier(RemovableWish(title: removeTitle) { remove(row.wish) })
                    }
                } label: {
                    Text(verbatim: content.decidedTitle(in: locale))
                        .font(.body.weight(.medium))
                        .tabularDigits()
                        .foregroundStyle(Theme.Color.text)
                        .frame(minHeight: Theme.minimumTarget)
                        .accessibilityHint(Text(verbatim: GoalsContent.decidedHint.text(in: locale)))
                        .accessibilityIdentifier("goals.decidedToggle")
                }
                .listRowBackground(Theme.Color.card)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.Color.muted)
            .textCase(nil)
    }

    private var removeTitle: String { GoalsContent.removeTitle.text(in: locale) }

    // MARK: Actions

    /// Takes the wish off the list at once; the toast brings it back as it was.
    private func remove(_ wish: Wish) {
        let message = GoalsContent.wishRemoved(wish.title, in: locale)
        let failed = GoalFormModel.somethingFailed.text(in: locale)
        Task {
            do {
                guard let token = try await model.deleteWish(wish.id) else { return }
                showUndoToast(UndoToast(message, length: .long) {
                    Task {
                        do {
                            try await model.restoreWish(token)
                        } catch {
                            log.error("Bringing a wish back failed: \(String(describing: error))")
                            failure = failed
                        }
                    }
                })
            } catch {
                log.error("Removing a wish failed: \(String(describing: error))")
                failure = failed
            }
        }
    }

    /// The trash in the goal's form: gone at once, back with "Отменить", main again if it was.
    private func delete(_ goal: Goal) {
        let message = GoalsContent.goalDeleted(goal.name, in: locale)
        let failed = GoalFormModel.somethingFailed.text(in: locale)
        Task {
            do {
                let token = try await model.deleteGoal(goal)
                showUndoToast(UndoToast(message, length: .long) {
                    Task {
                        do {
                            try await model.restoreGoal(token)
                        } catch {
                            log.error("Bringing a goal back failed: \(String(describing: error))")
                            failure = failed
                        }
                    }
                })
            } catch {
                log.error("Deleting a goal failed: \(String(describing: error))")
                failure = failed
            }
        }
    }

    /// "Купить", confirmed: the expense goes in, the goal closes, and the toast says what it cost.
    private func buy(_ goal: Goal) {
        let base = data.base
        let locale = locale
        let ok = GoalFormModel.okTitle.text(in: locale)
        let failed = GoalFormModel.somethingFailed.text(in: locale)
        Task {
            do {
                if let outcome = try await model.buyGoal(goal) {
                    let report = GoalPurchaseReport(goal: goal, impact: outcome.impact, base: base)
                    showUndoToast(UndoToast(report.text(in: locale), actionTitle: ok, length: .long) {})
                } else {
                    showUndoToast(UndoToast(GoalPurchasePlan.noAccount.text(in: locale), actionTitle: ok) {})
                }
            } catch {
                log.error("Buying a goal failed: \(String(describing: error))")
                failure = failed
            }
        }
    }
}

/// A wish leaves with a swipe to the left or from its long-press menu, as Android's swipe and long
/// press did; the toast can bring it back.
private struct RemovableWish: ViewModifier {
    let title: String
    var onRemove: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: onRemove) {
                    Label { Text(verbatim: title) } icon: { Image(systemName: Symbols.delete) }
                }
                .accessibilityIdentifier("goals.wish.remove")
            }
            .contextMenu {
                Button(role: .destructive, action: onRemove) {
                    Label { Text(verbatim: title) } icon: { Image(systemName: Symbols.delete) }
                }
                .accessibilityIdentifier("goals.wish.menuRemove")
            }
    }
}

// MARK: - Previews

#Preview("Samples") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            GoalsScreen(data: data)
                .navigationTitle(Text(AppTab.goals.title))
        }
    }
    .environment(model)
    .environment(AppRouter())
    .task { await model.start(command: .samples) }
}

#Preview("Samples, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            GoalsScreen(data: data)
                .navigationTitle(Text(AppTab.goals.title))
        }
    }
    .environment(model)
    .environment(AppRouter())
    .environment(\.locale, Locale(identifier: "ru"))
    .preferredColorScheme(.dark)
    .task { await model.start(command: .samples) }
}
