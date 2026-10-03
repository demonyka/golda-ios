import Foundation
import GoldaCore
import GoldaData
import SwiftUI
import Testing
import UIKit

@testable import Golda

/// The Accounts tab over the real app model: the sample books as the screen shows them, and
/// reconciling through the model, which the page then shows.
@MainActor @Suite(.timeLimit(.minutes(1))) struct AccountsAppTests {
    typealias F = HomeFixture

    private func samples() async throws -> (AppHarness, AppData) {
        let harness = try AppHarness()
        await harness.model.start(command: .samples, profileName: "Личный")
        return (harness, try await harness.data())
    }

    @Test func theSampleBooksOnTheAccountsTab() async throws {
        let (harness, data) = try await samples()
        let content = AccountsContent(data: data, today: harness.environment.today())

        #expect(content.sections.map { $0.rows.map(\.name) } == [
            ["Карта ₽", "Накопительный"],
            ["Мультивалютная USD", "Мультивалютная GEL"],
            ["Наличные ₾", "Кредитка", "Кредит"],
        ])
        #expect(content.sections.map { $0.label == nil } == [true, false, true])
        #expect(content.sections[1].label?.hasPrefix("Мультивалютная · ") == true)
        #expect(content.addRowJoinsLastSection)
        #expect(content.hero.advice == .payOffInsteadOfSaving(debt: "Кредитка", debtRate: 29.9, savings: "Накопительный", savingsRate: 12))

        let rows = content.sections.flatMap(\.rows)
        let card = try #require(rows.first { $0.name == "Карта ₽" })
        // 5 000 + 158 400 − 80 000 − 73 600 − 699 ₽, as on Android's screenshot.
        #expect(card.balance == "9\u{202F}101 ₽")
        #expect(card.subline.text(in: F.ru) == "Карта")
        // 330 000 ₽ since before October at 12 %, as on Android's screenshot.
        let savings = try #require(rows.first { $0.name == "Накопительный" })
        #expect(savings.subline.text(in: F.ru) == "+3\u{202F}363 ₽ за октябрь")
        #expect(savings.balance == "330\u{202F}000 ₽")
        let credit = try #require(rows.first { $0.name == "Кредитка" })
        #expect(credit.balance == "−15\u{202F}000 ₽")
    }

    @Test func aDifferentBalanceIsRecordedAndTheSameOneOnlyNotesTheTime() async throws {
        let (harness, data) = try await samples()
        let card = try #require(data.accounts.first { $0.name == "Карта ₽" })
        let gel = try #require(data.accounts.first { $0.name == "Мультивалютная GEL" })
        let operations = data.operations.count

        try await harness.model.reconcile(accountId: card.id, actualMinor: 900_000)
        await eventually { harness.model.data?.states[card.id]?.balanceMinor == 900_000 }
        let reconciled = try #require(harness.model.data)
        let page = try #require(AccountPageModel(data: reconciled, accountId: card.id, today: harness.environment.today()))
        #expect(page.balance == "9\u{202F}000 ₽")
        // The adjustment is the newest operation on the page, named and signed as the account sees it.
        let adjustment = try #require(page.days.first?.rows.first)
        #expect(adjustment.title == .reconciliation)
        #expect(adjustment.main == "−101 ₽")
        #expect(harness.model.data?.operations.count == operations + 1)

        // "Сходится": nothing recorded, only the time of the check.
        let gelBalance = try #require(data.states[gel.id]?.balanceMinor)
        try await harness.model.reconcile(accountId: gel.id, actualMinor: gelBalance)
        await eventually { harness.model.data?.accounts.first { $0.id == gel.id }?.reconciledAt == AppHarness.now }
        #expect(harness.model.data?.states[gel.id]?.balanceMinor == gelBalance)
        #expect(harness.model.data?.operations.count == operations + 1)
    }
}

/// Reconcile mode as the lead sees it: the whole shell on the Accounts tab, drawn in a real window
/// of the hosting app and saved to /tmp (never committed). The mode has no way in from the screen
/// until the Sunday reminder of stage 4, so the pictures are taken here.
@MainActor @Suite(.timeLimit(.minutes(1))) struct AccountsSnapshotTests {
    static let directory = URL(fileURLWithPath: "/tmp/golda-shots/B1", isDirectory: true)

    @Test func reconcileModeInBothLanguagesAndThemes() async throws {
        let harness = try AppHarness()
        await harness.model.start(command: .samples, profileName: "Личный")
        let data = try await harness.data()
        for language in ["ru", "en"] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                try await windowImage("reconcile-mode-\(language)", style: style) {
                    MainTabs(data: data, mic: StubMicModel(), tab: .accounts, reconciling: true)
                        .environment(harness.model)
                        .environment(\.locale, Locale(identifier: language))
                }
            }
        }
        // The rows stack at the largest text size: the balance and "Сходится" go under the name. A
        // window three screens tall, so the rows are in the picture as well as the hero.
        try await windowImage("reconcile-mode-ru-ax5", size: CGSize(width: 402, height: 2_600), style: .light) {
            NavigationStack {
                AccountsScreen(data: data, today: harness.environment.today(), reconcileMode: true, onAddAccount: {}, onEditAccount: { _ in })
            }
            .environment(harness.model)
            .environment(\.locale, Locale(identifier: "ru"))
            .dynamicTypeSize(.accessibility5)
        }
    }

    /// The view in a phone-sized window of the hosting app, its picture written to the directory.
    private func windowImage<V: View>(
        _ name: String, size: CGSize = CGSize(width: 402, height: 874), style: UIUserInterfaceStyle, @ViewBuilder _ content: () -> V
    ) async throws {
        // A hosted test bundle runs inside the app and has a scene; without one there is nothing to look at.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: content())
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(1_500))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let data = try #require(image.pngData())
        #expect(data.count > 10_000, "\(name) looks empty")
        let suffix = style == .dark ? "dark" : "light"
        try data.write(to: Self.directory.appendingPathComponent("hosted-\(name)-\(suffix).png"))
    }
}

/// Every line of the Accounts tab, the page and the sheet in both languages (CLAUDE.md).
@MainActor @Suite struct AccountsStringsTests {
    typealias F = HomeFixture

    @Test func theScreensLinesAreTranslated() {
        let lines: [(LocalizedStringResource, String, String)] = [
            (AccountsHero.caption, "Всего", "Total"),
            (AccountsScreen.addTitle, "Счёт", "Account"),
            (AccountsScreen.addLabel, "Добавить счёт", "Add account"),
            (AccountsScreen.reconcileTitle, "Сверка", "Reconciling"),
            (AccountsScreen.reconcileHint, "Совпало с банком — «Сходится». Нет — нажми на счёт.", "Matches the bank: “Matches”. Doesn’t: tap the account."),
            (AccountsScreen.reconcileRowHint, "Введи, сколько показывает банк", "Type what the bank shows"),
            (AccountsScreen.allReconciled, "Все счета сверены", "All accounts reconciled"),
            (AccountsScreen.okTitle, "ОК", "OK"),
            (ReconcileMark.matchTitle, "Сходится", "Matches"),
            (ReconcileMark.checkedLabel, "Сверено", "Checked"),
            (AccountRowModel.inBudgetLabel, "Входит в «Можно сегодня»", "Counts in “Safe to spend today”"),
            (AccountPage.editTitle, "Изменить", "Edit"),
            (AccountPageHero.reconcileTitle, "Сверить", "Reconcile"),
            (ReconcileSheet.question, "Сколько на самом деле?", "How much is really there?"),
            (ReconcileSheet.cancelTitle, "Отмена", "Cancel"),
            (ReconcileSheet.signLabel, "Сменить знак", "Change the sign"),
        ]
        for (resource, russian, english) in lines {
            #expect(resource.text(in: F.ru) == russian)
            #expect(resource.text(in: F.en) == english)
        }
    }

    @Test func everyAccountTypeHasANameInBothLanguages() {
        let expected: [AccountType: (String, String)] = [
            .card: ("Карта", "Card"), .cash: ("Наличные", "Cash"), .savings: ("Накопительный", "Savings"),
            .credit: ("Кредитка", "Credit card"), .loan: ("Кредит", "Loan"),
        ]
        for type in AccountType.allCases {
            #expect(AccountTypeTitle.resource(type).text(in: F.ru) == expected[type]?.0)
            #expect(AccountTypeTitle.resource(type).text(in: F.en) == expected[type]?.1)
        }
    }
}
