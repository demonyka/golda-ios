import XCTest

/// The flows a person cares about, end to end on the made-up person's books, each read back where
/// the person would look: the hero number on Home, the balances on Accounts. Record an expense;
/// reconcile an account and take it back; add an account and fund it by transfer; change the main
/// currency; erase everything and start again; keep two profiles apart; book a note by voice.
final class EndToEndUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// An expense from "+" lowers what is safe to spend today, and the account it came from.
    @MainActor
    func testAnExpenseLowersTheHeroAndItsAccount() {
        let walk = Walk(shotsName: "e2e-expense")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        let safe = firstWholeNumber(in: walk.homeHero.label) ?? 0
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        let card = walk.accountRow("Карта ₽")
        walk.reveal(card)
        XCTAssertTrue(card.label.hasSuffix(", 9101 " + walk.text("Russian rubles", "российского рубля")) || card.label.contains("9101"), card.label)
        let total = firstWholeNumber(in: walk.accountsHero.label) ?? 0

        // 500 ₽ for groceries from the ruble card.
        walk.tapToolbar("add")
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("500")
        app.buttons["entry.account"].tap()
        walk.button(startingWith: "Карта ₽").tap()
        XCTAssertTrue(waitUntil { app.buttons["entry.account"].value as? String == "Карта ₽" })
        walk.dismissKeyboard()
        app.buttons["entry.category.groceries"].tap()
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[walk.text("Undo", "Отменить")].waitForExistence(timeout: 5))

        // The account and the total fall by the 500 ₽ at once.
        XCTAssertTrue(waitUntil { card.label.contains("8601") }, card.label)
        XCTAssertTrue(waitUntil { firstWholeNumber(in: walk.accountsHero.label) == total - 500 }, walk.accountsHero.label)
        walk.shoot("accounts-after")

        // Home: the newest row, and the hero is 500 ₽ lower.
        walk.openTab("Home", "Главная", waitingFor: "home.hero")
        XCTAssertTrue(waitUntil { walk.operations.firstMatch.label.hasPrefix(walk.text("Groceries,", "Продукты,")) }, walk.operations.firstMatch.label)
        XCTAssertTrue(waitUntil { firstWholeNumber(in: walk.homeHero.label) == safe - 500 }, "\(safe) → \(walk.homeHero.label)")
        walk.shoot("home-after")
    }

    /// The bank shows 9 000 ₽: the reconciliation books the difference; deleting that adjustment
    /// takes the account back to 9 101 ₽, and the toast's "Undo" puts it back again.
    @MainActor
    func testAReconciliationAndItsUndo() {
        let walk = Walk(shotsName: "e2e-reconcile")
        let app = walk.app
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        let total = firstWholeNumber(in: walk.accountsHero.label) ?? 0
        let card = walk.accountRow("Карта ₽")
        walk.reveal(card)
        card.tap()
        let page = walk.any("account.hero")
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(firstWholeNumber(in: page.label), 9101)

        app.buttons["account.reconcile"].tap()
        let actual = app.textFields["reconcile.amount"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        walk.type("9000", into: actual)
        app.buttons["reconcile.save"].tap()
        XCTAssertTrue(actual.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { firstWholeNumber(in: page.label) == 9000 }, page.label)
        let adjustment = app.buttons.matching(identifier: "account.operation").firstMatch
        XCTAssertTrue(waitUntil { adjustment.label.hasPrefix(walk.text("Reconciliation,", "Сверка,")) }, adjustment.label)
        walk.shoot("reconciled")

        // Taken back: the adjustment's sheet deletes it, and the balance is what it was.
        adjustment.tap()
        let delete = app.buttons["bookkeeping.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { firstWholeNumber(in: page.label) == 9101 }, page.label)
        let undo = app.buttons[walk.text("Undo", "Вернуть")]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        walk.shoot("adjustment-deleted")

        // And "Undo" in the toast brings the reconciliation back.
        undo.tap()
        XCTAssertTrue(waitUntil { firstWholeNumber(in: page.label) == 9000 }, page.label)
        walk.back()
        XCTAssertTrue(waitUntil { firstWholeNumber(in: walk.accountsHero.label) == total - 101 }, walk.accountsHero.label)
    }

    /// A new cash account starts empty; a transfer from the lari card puts 100 ₾ on it, and the card
    /// gives them up.
    @MainActor
    func testANewAccountIsFundedByATransfer() {
        let walk = Walk(shotsName: "e2e-new-account")
        let app = walk.app
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        let source = walk.accountRow("Мультивалютная GEL")
        walk.reveal(source)
        let sourceBefore = source.label

        let add = app.buttons["accounts.add"]
        walk.reveal(add)
        add.tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        walk.type("Wallet", into: name)
        app.buttons["accountForm.type.cash"].tap()
        app.buttons["accountForm.save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        let wallet = walk.accountRow("Wallet")
        walk.reveal(wallet)
        XCTAssertTrue(wallet.label.hasSuffix(" 0 " + walk.text("Georgian laris", "грузинских лари")) || wallet.label.hasSuffix(", 0 " + walk.text("Georgian laris", "грузинских лари")), wallet.label)

        walk.tapToolbar("add")
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        app.segmentedControls["entry.type"].buttons[walk.text("Transfer", "Перевод")].tap()
        app.buttons["entry.from"].tap()
        walk.button(startingWith: "Мультивалютная GEL · ").tap()
        app.buttons["entry.to"].tap()
        walk.button(startingWith: "Wallet · ").tap()
        XCTAssertTrue(waitUntil { (app.buttons["entry.to"].value as? String ?? "").hasPrefix("Wallet") })
        walk.type("100", into: amount)
        walk.shoot("transfer")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))

        XCTAssertTrue(waitUntil { wallet.exists && wallet.label.hasSuffix(" 100 " + walk.text("Georgian laris", "грузинских лари")) }, wallet.label)
        XCTAssertTrue(waitUntil { source.label != sourceBefore }, "the card gives the 100 ₾ up: \(source.label)")
        walk.shoot("funded")
    }

    /// Lari as the main currency: Home's and Accounts' big numbers are in lari; back to rubles,
    /// they are in rubles again.
    @MainActor
    func testTheMainCurrencyChangesTheBigNumbers() {
        let walk = Walk(shotsName: "e2e-main-currency")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        let rubles = walk.text("rubles", "рубл"), laris = walk.text("lari", "лари")
        XCTAssertTrue(walk.homeHero.label.localizedCaseInsensitiveContains(rubles), walk.homeHero.label)

        func pickMain(_ code: String) {
            walk.tapToolbar("settings")
            let main = app.buttons["settings.main"]
            XCTAssertTrue(main.waitForExistence(timeout: 5))
            main.tap()
            app.buttons["settings.pick.\(code)"].tap()
            XCTAssertTrue(waitUntil { main.label.contains(code) }, main.label)
            app.buttons["settings.done"].tap()
            XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 5))
        }

        pickMain("GEL")
        XCTAssertTrue(waitUntil { walk.homeHero.label.localizedCaseInsensitiveContains(laris) }, walk.homeHero.label)
        walk.shoot("home-lari")
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        let total = walk.accountsHero.label
        XCTAssertTrue(firstPhrase(total).localizedCaseInsensitiveContains(laris), total)
        walk.shoot("accounts-lari")

        pickMain("RUB")
        XCTAssertTrue(waitUntil { firstPhrase(walk.accountsHero.label).localizedCaseInsensitiveContains(rubles) }, walk.accountsHero.label)
        walk.openTab("Home", "Главная", waitingFor: "home.hero")
        XCTAssertTrue(firstPhrase(walk.homeHero.label).localizedCaseInsensitiveContains(rubles), walk.homeHero.label)
    }

    /// "Erase everything" goes back to the welcome screen; a new start has empty books, and an
    /// account with an expense works from there.
    @MainActor
    func testEraseEverythingAndStartAgain() {
        let walk = Walk(shotsName: "e2e-erase")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        walk.tapToolbar("settings")
        let erase = app.buttons["settings.erase"]
        walk.reveal(erase)
        erase.tap()
        let question = app.alerts.firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.buttons[walk.text("Erase", "Стереть")].tap()
        let start = app.buttons["welcome.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        walk.shoot("welcome")
        start.tap()

        // Empty books: nothing on Home, nothing on Accounts but "+ Account".
        XCTAssertTrue(walk.any("home.empty").waitForExistence(timeout: 10))
        XCTAssertEqual(walk.operations.count, 0)
        XCTAssertEqual(firstWholeNumber(in: walk.homeHero.label), 0, walk.homeHero.label)
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        XCTAssertEqual(app.buttons.matching(identifier: "accounts.account").count, 0)
        walk.shoot("accounts-empty")

        // A card with 30 000 ₽: there is something to spend today, and an expense spends it.
        app.buttons["accounts.add"].tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        walk.type("Card", into: name)
        walk.type("30000", into: app.textFields["accountForm.opening"])
        app.buttons["accountForm.save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(walk.accountRow("Card").waitForExistence(timeout: 5))
        walk.openTab("Home", "Главная", waitingFor: "home.hero")
        XCTAssertTrue(waitUntil { (firstWholeNumber(in: walk.homeHero.label) ?? 0) > 0 }, walk.homeHero.label)
        let safe = firstWholeNumber(in: walk.homeHero.label) ?? 0

        walk.tapToolbar("add")
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("100")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { walk.operations.count == 1 })
        XCTAssertTrue(waitUntil { firstWholeNumber(in: walk.homeHero.label) == safe - 100 }, "\(safe) → \(walk.homeHero.label)")
        walk.shoot("started-again")
    }

    /// A second profile has books of its own: its account and expense never reach the first one,
    /// and switching back and forth shows each its own numbers.
    @MainActor
    func testEachProfileKeepsItsOwnNumbers() {
        let walk = Walk(shotsName: "e2e-profiles")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        let personalHome = walk.homeHero.label
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        let personalTotal = walk.accountsHero.label
        let menu = app.buttons["profileMenu"]

        // "Trip", from the menu, opens at once with nothing in it.
        menu.tap()
        app.buttons["profileMenu.new"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("Trip")
        alert.buttons[walk.text("Create", "Создать")].tap()
        XCTAssertTrue(waitUntil { app.buttons.matching(identifier: "accounts.account").count == 0 })
        XCTAssertNotEqual(walk.accountsHero.label, personalTotal)

        // Its own cash, 1 000 ₾, and 100 ₾ spent from it.
        app.buttons["accounts.add"].tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        walk.type("Trip cash", into: name)
        app.buttons["accountForm.type.cash"].tap()
        walk.type("1000", into: app.textFields["accountForm.opening"])
        app.buttons["accountForm.save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        walk.tapToolbar("add")
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("100")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        let tripCash = walk.accountRow("Trip cash")
        XCTAssertTrue(waitUntil { tripCash.exists && tripCash.label.contains(" 900 ") }, tripCash.label)
        let tripTotal = walk.accountsHero.label
        walk.shoot("trip-accounts")

        // Back in "Personal": the samples' numbers, untouched.
        menu.tap()
        app.buttons[walk.text("Personal", "Личный")].tap()
        XCTAssertTrue(waitUntil { walk.accountsHero.label == personalTotal }, walk.accountsHero.label)
        XCTAssertFalse(tripCash.exists)
        walk.openTab("Home", "Главная", waitingFor: "home.hero")
        XCTAssertTrue(waitUntil { walk.homeHero.label == personalHome }, walk.homeHero.label)

        // And "Trip" again: its own.
        menu.tap()
        app.buttons["Trip"].tap()
        XCTAssertTrue(walk.any("home.empty").waitForExistence(timeout: 5) || walk.operations.count == 1)
        XCTAssertTrue(waitUntil { walk.operations.count == 1 }, "the trip's one expense")
        XCTAssertNotEqual(walk.homeHero.label, personalHome)
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        XCTAssertTrue(waitUntil { walk.accountsHero.label == tripTotal }, walk.accountsHero.label)
        XCTAssertTrue(tripCash.label.contains(" 900 "), tripCash.label)
    }

    /// "Шаурма 15 лари" by voice (the stub): booked from the lari, on Home with the toast; the hero
    /// falls, and "Undo" puts everything back. An expense from "+" just before has its own toast,
    /// and the note's replaces it rather than covering it.
    @MainActor
    func testAVoiceNoteIsBookedAndTakenBack() {
        let walk = Walk(extra: ["-golda.voiceStub=shawarma"], shotsName: "e2e-voice")
        let app = walk.app
        let mic = walk.mic
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 5))
        let shawarmas = app.buttons.matching(identifier: "home.operation").matching(NSPredicate(format: "label BEGINSWITH %@", "Шаурма,"))
        XCTAssertTrue(shawarmas.firstMatch.waitForExistence(timeout: 5))
        let count = shawarmas.count

        let untouched = walk.homeHero.label
        walk.tapToolbar("add")
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("5")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        let formToast = walk.staticText(containing: " · 5 ")
        XCTAssertTrue(formToast.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { walk.homeHero.label != untouched })
        let safe = firstWholeNumber(in: walk.homeHero.label) ?? 0

        mic.tap()
        mic.tap()
        let toast = walk.staticText(containing: "Шаурма 15 ₾")
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertFalse(formToast.exists, "the note's toast replaces the form's")
        let undos = app.buttons.matching(NSPredicate(format: "label == %@", walk.text("Undo", "Отменить")))
        XCTAssertEqual(undos.count, 1, "one toast at a time")
        walk.shoot("booked")
        XCTAssertTrue(waitUntil { shawarmas.count == count + 1 }, "the note's row on Home")
        XCTAssertTrue(waitUntil { (firstWholeNumber(in: walk.homeHero.label) ?? 0) < safe }, walk.homeHero.label)

        app.buttons[walk.text("Undo", "Отменить")].tap()
        XCTAssertTrue(waitUntil { shawarmas.count == count }, "undo takes the row away")
        XCTAssertTrue(waitUntil { firstWholeNumber(in: walk.homeHero.label) == safe }, walk.homeHero.label)
    }

    /// The first sentence of a hero's VoiceOver label after its caption: the big number in words.
    private func firstPhrase(_ label: String) -> String {
        let sentences = label.components(separatedBy: ". ")
        return sentences.count > 1 ? sentences[1] : label
    }
}
