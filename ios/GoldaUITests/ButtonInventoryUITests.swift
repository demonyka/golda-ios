import XCTest

/// Every interactive element of what the owner asked to be complete first (D35), tapped the way a
/// person would from a fresh launch on the made-up person's books, each with what it visibly does:
/// Home with the tab bar and the toolbar ("+", the gear, the profile menu), the operation form,
/// Accounts and an account's page, the profile menu and the profiles screens, the settings, and the
/// mic. A button that does nothing, leads nowhere or leaves no way back fails here.
///
/// Each part starts from its own launch, so one failure says where. With `GOLDA_SHOTS_DIR` set for
/// the runner, every step is also pictured (`WalkthroughSupport`).
final class ButtonInventoryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Home, the tab bar and the toolbar

    @MainActor
    func testHomeTheTabBarAndTheToolbar() {
        let walk = Walk(shotsName: "home")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        XCTAssertTrue(app.navigationBars[walk.text("Home", "Главная")].exists, "the large title")
        XCTAssertTrue(walk.mic.isHittable, "the mic on Home")
        walk.shoot("home")

        // Each tab opens its own screen.
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        XCTAssertTrue(walk.mic.isHittable, "the mic on Accounts")
        walk.openTab("Goals", "Цели", waitingFor: "goals.hero")
        walk.openTab("Insights", "Аналитика", waitingFor: "insights.ring")
        XCTAssertTrue(walk.mic.isHittable, "the mic on Insights")
        walk.openTab("Home", "Главная", waitingFor: "home.hero")

        // "+": a new operation; "Cancel" closes it and records nothing.
        let count = walk.operations.count
        walk.tapToolbar("add")
        XCTAssertTrue(app.navigationBars[walk.text("New operation", "Новая операция")].waitForExistence(timeout: 5))
        walk.shoot("plus")
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(walk.operations.count, count)

        // The gear: this phone's settings; "Done" closes them.
        walk.tapToolbar("settings")
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        walk.shoot("gear")
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 5))

        // The profile menu: the profiles with the open one ticked, a new one, the profiles screen.
        let menu = app.buttons["profileMenu"]
        XCTAssertEqual(menu.label, walk.text("Profile: Personal", "Профиль: Личный"))
        menu.tap()
        XCTAssertTrue(app.buttons["profileMenu.new"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profileMenu.manage"].exists)
        let personal = app.buttons[walk.text("Personal", "Личный")]
        XCTAssertTrue(personal.exists)
        walk.shoot("profile-menu")
        personal.tap()
        XCTAssertTrue(app.buttons["profileMenu.new"].waitForNonExistence(timeout: 5), "picking the open profile closes the menu")
        XCTAssertEqual(menu.label, walk.text("Profile: Personal", "Профиль: Личный"))

        // An operation's row: the form with that operation; "Cancel" changes nothing.
        let first = walk.operations.firstMatch
        let title = String(first.label.prefix { $0 != "," })
        first.tap()
        XCTAssertTrue(app.navigationBars[walk.text("Operation", "Операция")].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["entry.note"].value as? String, title)
        XCTAssertTrue(app.buttons["entry.delete"].exists, "an operation can be deleted from its form")
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(walk.operations.firstMatch.label.hasPrefix(title + ","))

        // At the end of the list, the last operation is clear of the mic and the tab bar.
        var last = ""
        for _ in 0..<15 {
            app.swipeUp()
            let label = walk.operations.allElementsBoundByIndex.filter(\.exists).max { $0.frame.maxY < $1.frame.maxY }?.label ?? ""
            if label == last { break }
            last = label
        }
        let lowest = walk.operations.allElementsBoundByIndex.filter(\.exists).max { $0.frame.maxY < $1.frame.maxY }
        XCTAssertNotNil(lowest)
        if let lowest { XCTAssertLessThanOrEqual(lowest.frame.maxY, walk.mic.frame.minY, "the last row under the mic") }
        walk.shoot("home-bottom")
    }

    // MARK: The operation form

    @MainActor
    func testTheOperationFormEveryControl() {
        let walk = Walk(shotsName: "entry")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        let before = firstWholeNumber(in: walk.homeHero.label)

        walk.tapToolbar("add")
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "a new operation starts with its amount")
        let save = app.buttons["entry.save"]
        XCTAssertFalse(save.isEnabled, "nothing to save yet")
        XCTAssertFalse(app.buttons["entry.consider"].isEnabled, "nothing to weigh up yet")
        amount.typeText("12")
        XCTAssertTrue(save.isEnabled)

        // The account pill and the currency menu: a purchase in lari from the dollar card shows
        // what the card is charged, and the bank's figure can be typed over it.
        app.buttons["entry.account"].tap()
        walk.button(startingWith: "Мультивалютная USD").tap()
        XCTAssertTrue(waitUntil { app.buttons["entry.account"].value as? String == "Мультивалютная USD" })
        app.buttons["entry.currency"].tap()
        walk.button(startingWith: "₾ GEL").tap()
        XCTAssertTrue(waitUntil { app.buttons["entry.currency"].value as? String == "₾ GEL" })
        let second = app.buttons["entry.second"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        walk.shoot("charged")
        second.tap()
        XCTAssertTrue(app.textFields["entry.second.field"].waitForExistence(timeout: 5))
        walk.dismissKeyboard()
        XCTAssertTrue(second.waitForExistence(timeout: 5), "the charge folds back into its line")

        // The day: a calendar with a way back.
        let date = app.buttons["entry.date"]
        let today = date.value as? String
        date.tap()
        XCTAssertTrue(app.navigationBars[walk.text("Date", "Дата")].waitForExistence(timeout: 5))
        walk.shoot("date")
        app.buttons["entry.date.done"].tap()
        XCTAssertTrue(app.navigationBars[walk.text("Date", "Дата")].waitForNonExistence(timeout: 5))
        XCTAssertEqual(date.value as? String, today)

        // What it was, and its category.
        walk.type("Lunch", into: app.textFields["entry.note"])
        walk.dismissKeyboard()
        let category = app.buttons["entry.category.eating_out"]
        category.tap()
        XCTAssertTrue(waitUntil { category.isSelected })
        walk.shoot("expense")

        // The type: income has its own categories and no currency menu; a transfer has its route
        // and the swap between its ends.
        let types = app.segmentedControls["entry.type"]
        types.buttons[walk.text("Income", "Доход")].tap()
        XCTAssertTrue(app.buttons["entry.category.salary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["entry.currency"].exists)
        types.buttons[walk.text("Transfer", "Перевод")].tap()
        let from = app.buttons["entry.from"], to = app.buttons["entry.to"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        let (start, end) = (from.value as? String, to.value as? String)
        XCTAssertNotEqual(start, end)
        app.buttons["entry.swap"].tap()
        XCTAssertTrue(waitUntil { from.value as? String == end && to.value as? String == start }, "the swap swaps")
        walk.shoot("transfer")
        types.buttons[walk.text("Expense", "Расход")].tap()
        XCTAssertTrue(app.buttons["entry.consider"].waitForExistence(timeout: 5))

        // "Not sure", its way back, and "Buy": the expense is recorded and announced with "Undo".
        app.buttons["entry.consider"].tap()
        XCTAssertTrue(app.buttons["entry.buy"].waitForExistence(timeout: 5))
        XCTAssertFalse(types.exists, "no type while deciding")
        app.buttons["entry.back"].tap()
        XCTAssertTrue(types.waitForExistence(timeout: 5))
        app.buttons["entry.consider"].tap()
        let buy = app.buttons["entry.buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 5))
        walk.shoot("not-sure")
        buy.tap()
        XCTAssertTrue(buy.waitForNonExistence(timeout: 5))
        let undo = app.buttons[walk.text("Undo", "Отменить")]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(undo.frame.maxY, walk.mic.frame.minY, "the toast floats above the mic")
        walk.shoot("bought")
        XCTAssertTrue(waitUntil { walk.operations.firstMatch.label.hasPrefix("Lunch,") }, walk.operations.firstMatch.label)
        XCTAssertTrue(waitUntil { firstWholeNumber(in: walk.homeHero.label) ?? 0 < before ?? 0 }, "the hero falls")
        undo.tap()
        XCTAssertTrue(waitUntil { !walk.operations.firstMatch.label.hasPrefix("Lunch,") }, "undo takes it back")
        XCTAssertTrue(waitUntil { firstWholeNumber(in: walk.homeHero.label) == before }, walk.homeHero.label)

        // "Think" and "Skip": each closes the form with a toast and records nothing.
        for (answer, words) in [("entry.think", walk.text("decide in", "решить через")), ("entry.skip", "Велосипед")] {
            walk.tapToolbar("add")
            XCTAssertTrue(amount.waitForExistence(timeout: 5))
            amount.typeText("20")
            app.buttons["entry.consider"].tap()
            let button = app.buttons[answer]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntil { button.isEnabled })
            button.tap()
            XCTAssertTrue(button.waitForNonExistence(timeout: 5), answer)
            XCTAssertTrue(walk.staticText(containing: words).waitForExistence(timeout: 5), answer)
            XCTAssertEqual(firstWholeNumber(in: walk.homeHero.label), before, "\(answer) spends nothing")
        }

        // An operation's form: "Save" keeps the change, the trash deletes, "Undo" brings it back.
        let coffee = walk.operations.firstMatch
        XCTAssertTrue(coffee.label.hasPrefix("Кофе,"), coffee.label)
        coffee.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let note = app.textFields["entry.note"]
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { note.tap() }
        note.typeText(" to go")
        walk.dismissKeyboard()
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { coffee.label.hasPrefix("Кофе to go,") }, coffee.label)
        coffee.tap()
        let delete = app.buttons["entry.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { !walk.operations.firstMatch.label.hasPrefix("Кофе to go,") })
        app.buttons[walk.text("Undo", "Вернуть")].tap()
        XCTAssertTrue(waitUntil { walk.operations.firstMatch.label.hasPrefix("Кофе to go,") }, "back where it was")
    }

    // MARK: Accounts and an account's page

    @MainActor
    func testAccountsAndAnAccountsPage() {
        let walk = Walk(shotsName: "accounts")
        let app = walk.app
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        XCTAssertTrue(app.navigationBars[walk.text("Accounts", "Счета")].exists, "the large title")
        walk.shoot("accounts")

        // "+ Account" at the end, clear of the mic: the form, and "Cancel" adds nothing.
        let add = app.buttons["accounts.add"]
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertTrue(add.isHittable)
        XCTAssertLessThanOrEqual(add.frame.maxY, walk.mic.frame.minY, "the last row under the mic")
        walk.shoot("accounts-bottom")
        let rows = app.buttons.matching(identifier: "accounts.account").count
        add.tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["accountForm.save"].isEnabled, "no name yet")
        app.buttons["accountForm.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "accounts.account").count, rows)

        // A row: the account's page, with no mic and a way back.
        let card = walk.accountRow("Карта ₽")
        walk.reveal(card)
        card.tap()
        let page = walk.any("account.hero")
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Карта ₽"].exists)
        XCTAssertFalse(walk.mic.exists && walk.mic.isHittable, "a pushed page carries no mic")
        let balance = page.label
        walk.shoot("page")

        // "Edit": the account's form with its trash, which asks first.
        app.buttons["account.edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Карта ₽")
        app.buttons["accountForm.delete"].tap()
        let question = app.alerts.firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        walk.shoot("delete-account-question")
        question.buttons[walk.text("Cancel", "Отмена")].tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 5))
        app.buttons["accountForm.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertEqual(page.label, balance)

        // "Reconcile": the sheet; the sign key flips what is typed; "Cancel" records nothing.
        app.buttons["account.reconcile"].tap()
        let actual = app.textFields["reconcile.amount"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        let confirm = app.buttons["reconcile.save"]
        XCTAssertEqual(confirm.label, walk.text("It matches", "Сходится"))
        walk.type("9000", into: actual)
        XCTAssertTrue(waitUntil { confirm.label.contains("101") }, "the difference to record: \(confirm.label)")
        let unsigned = confirm.label
        app.buttons["reconcile.sign"].tap()
        XCTAssertTrue(waitUntil { confirm.label != unsigned }, "the sign changes what would be recorded")
        walk.shoot("reconcile")
        app.buttons["reconcile.cancel"].tap()
        XCTAssertTrue(actual.waitForNonExistence(timeout: 5))
        XCTAssertEqual(page.label, balance)

        // "It matches" closes the sheet and records nothing.
        app.buttons["account.reconcile"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertEqual(page.label, balance)

        // An operation on the page: the form over the page, and back on the page.
        let operation = app.buttons.matching(identifier: "account.operation").firstMatch
        walk.reveal(operation)
        operation.tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 5))
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Карта ₽"].exists)

        // Back on the list; the loan's page has the early-repayment calculator, which closes.
        walk.back()
        XCTAssertTrue(walk.accountsHero.waitForExistence(timeout: 5))
        let loan = walk.accountRow("Кредит")
        walk.reveal(loan)
        loan.tap()
        let prepay = app.buttons["debt.prepay"]
        walk.reveal(prepay)
        walk.shoot("loan")
        prepay.tap()
        XCTAssertTrue(app.textFields["prepay.amount"].waitForExistence(timeout: 5))
        walk.shoot("prepay")
        app.buttons["prepay.done"].tap()
        XCTAssertTrue(app.textFields["prepay.amount"].waitForNonExistence(timeout: 5))
        walk.back()
        // Back on the list, scrolled down to the loan as it was left.
        XCTAssertTrue(loan.waitForExistence(timeout: 5))
        XCTAssertFalse(prepay.exists)
    }

    // MARK: The profile menu and the profiles screens

    @MainActor
    func testTheProfileMenuAndTheProfilesScreens() {
        let walk = Walk(shotsName: "profiles")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        let samples = walk.homeHero.label
        let menu = app.buttons["profileMenu"]

        // "New profile": the name first; "Cancel" creates nothing.
        menu.tap()
        app.buttons["profileMenu.new"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let create = alert.buttons[walk.text("Create", "Создать")]
        XCTAssertFalse(create.isEnabled, "no name yet")
        alert.buttons[walk.text("Cancel", "Отмена")].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertEqual(walk.homeHero.label, samples)

        // Named, it opens at once with nothing in it; the menu takes the app back.
        menu.tap()
        app.buttons["profileMenu.new"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("Trip")
        walk.shoot("new-profile")
        create.tap()
        XCTAssertTrue(walk.any("home.empty").waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, walk.text("Profile: Trip", "Профиль: Trip"))
        menu.tap()
        app.buttons[walk.text("Personal", "Личный")].tap()
        XCTAssertTrue(waitUntil { walk.homeHero.label == samples }, "back on the samples")

        // "Manage profiles": the list, a profile's own screen and every row on it.
        menu.tap()
        app.buttons["profileMenu.manage"].tap()
        let done = app.buttons["profiles.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let rows = app.buttons.matching(identifier: "profiles.row")
        XCTAssertEqual(rows.count, 2)
        walk.shoot("profiles")
        let trip = rows.matching(NSPredicate(format: "label == %@", "Trip")).firstMatch
        trip.tap()
        XCTAssertTrue(app.navigationBars["Trip"].waitForExistence(timeout: 5))
        walk.shoot("profile")

        app.buttons["profile.name"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(alert.textFields.firstMatch.value as? String, "Trip")
        alert.buttons[walk.text("Cancel", "Отмена")].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))

        for (row, sheet) in [("profile.rate", "rateSheet"), ("profile.taxHours", "taxHoursSheet"), ("profile.markup", "markupSheet")] {
            walk.reveal(app.buttons[row])
            app.buttons[row].tap()
            let cancel = app.buttons["\(sheet).cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), sheet)
            XCTAssertTrue(app.buttons["\(sheet).save"].exists, sheet)
            walk.shoot(sheet)
            cancel.tap()
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), sheet)
        }

        // Payday: a tap on a day picks it and closes the sheet.
        let payday = app.buttons["profile.payday"]
        walk.reveal(payday)
        let paydayBefore = payday.label
        payday.tap()
        let day = app.buttons["dayGrid.20"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        XCTAssertTrue(day.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { payday.label != paydayBefore }, payday.label)

        // "+ Payment": the form, which "Cancel" closes.
        let addPayment = app.buttons["profile.addPayment"]
        walk.reveal(addPayment)
        addPayment.tap()
        XCTAssertTrue(app.buttons["obligationForm.cancel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["obligationForm.save"].isEnabled, "nothing to add yet")
        app.buttons["obligationForm.cancel"].tap()
        XCTAssertTrue(app.buttons["obligationForm.cancel"].waitForNonExistence(timeout: 5))

        // Deleting asks first; "Cancel" keeps it.
        let delete = app.buttons["profile.delete"]
        walk.reveal(delete)
        XCTAssertTrue(delete.isEnabled)
        delete.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons[walk.text("Cancel", "Отмена")].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))

        // "Make active" opens it in the whole app.
        let makeActive = app.buttons["profile.makeActive"]
        walk.reveal(makeActive)
        makeActive.tap()
        XCTAssertTrue(walk.any("profile.active").waitForExistence(timeout: 5))
        walk.back()

        // The rows' own actions: "Make active" on a swipe right; "Rename" and "Delete profile" on a
        // swipe left.
        let personal = rows.matching(NSPredicate(format: "label == %@", walk.text("Personal", "Личный"))).firstMatch
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        personal.swipeRight()
        app.buttons[walk.text("Make active", "Сделать активным")].tap()
        XCTAssertTrue(rows.matching(NSPredicate(format: "label BEGINSWITH %@", walk.text("Personal, ", "Личный, "))).firstMatch.waitForExistence(timeout: 5))
        trip.swipeLeft()
        app.buttons[walk.text("Rename", "Переименовать")].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons[walk.text("Cancel", "Отмена")].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        trip.swipeLeft()
        app.buttons[walk.text("Delete profile", "Удалить профиль")].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        walk.shoot("delete-profile-question")
        alert.buttons[walk.text("Delete", "Удалить")].tap()
        XCTAssertTrue(trip.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)

        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { walk.homeHero.label == samples })
        XCTAssertEqual(menu.label, walk.text("Profile: Personal", "Профиль: Личный"))
    }

    // MARK: Settings

    @MainActor
    func testEverySettingsRow() {
        let walk = Walk(shotsName: "settings")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        walk.tapToolbar("settings")
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        walk.shoot("settings")

        // Where I am: each row opens its pick, which closes with a pick or "Done".
        let local = app.buttons["settings.local"]
        local.tap()
        let usd = app.buttons["settings.pick.USD"]
        XCTAssertTrue(usd.waitForExistence(timeout: 5))
        usd.tap()
        XCTAssertTrue(usd.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { local.label.contains("$ USD") }, local.label)
        local.tap()
        XCTAssertTrue(app.buttons["settings.pick.GEL"].waitForExistence(timeout: 5))
        app.buttons["settings.pick.GEL"].tap()
        XCTAssertTrue(waitUntil { local.label.contains("₾ GEL") }, local.label)
        app.buttons["settings.main"].tap()
        XCTAssertTrue(app.buttons["settings.pick.done"].waitForExistence(timeout: 5))
        app.buttons["settings.pick.done"].tap()
        XCTAssertTrue(app.buttons["settings.pick.done"].waitForNonExistence(timeout: 5))
        app.buttons["settings.shown"].tap()
        XCTAssertTrue(app.switches["settings.shown.EUR"].waitForExistence(timeout: 5))
        app.buttons["settings.shown.done"].tap()
        XCTAssertTrue(app.buttons["settings.shown.done"].waitForNonExistence(timeout: 5))

        // The rates: a refresh says how it went (offline here).
        let refresh = app.buttons["settings.refreshRates"]
        walk.reveal(refresh)
        refresh.tap()
        XCTAssertTrue(walk.any("settings.notice").waitForExistence(timeout: 15))

        // Voice: the key and the model sheets close with "Cancel"; the consent switch flips.
        let key = app.buttons["settings.key"]
        walk.reveal(key)
        key.tap()
        XCTAssertTrue(app.buttons["settings.key.cancel"].waitForExistence(timeout: 5))
        app.buttons["settings.key.cancel"].tap()
        XCTAssertTrue(app.buttons["settings.key.cancel"].waitForNonExistence(timeout: 5))
        let model = app.buttons["settings.model"]
        walk.reveal(model)
        model.tap()
        XCTAssertTrue(app.buttons["settings.model.cancel"].waitForExistence(timeout: 5))
        app.buttons["settings.model.cancel"].tap()
        XCTAssertTrue(app.buttons["settings.model.cancel"].waitForNonExistence(timeout: 5))
        let consent = app.switches["settings.voiceConsent"]
        walk.reveal(consent)
        let consentBefore = consent.value as? String
        walk.flip(consent)
        XCTAssertNotEqual(consent.value as? String, consentBefore)

        // Data: the reminder flips; the file rows are checked in their own test.
        let reminder = app.switches["settings.reminder"]
        walk.reveal(reminder)
        let reminderBefore = reminder.value as? String
        walk.flip(reminder)
        XCTAssertNotEqual(reminder.value as? String, reminderBefore)
        walk.shoot("settings-data")

        // About: the licences page and its way back.
        let licences = app.buttons["settings.licences.row"]
        walk.reveal(licences)
        licences.tap()
        XCTAssertTrue(walk.any("settings.licences").waitForExistence(timeout: 5))
        walk.back()
        XCTAssertTrue(licences.waitForExistence(timeout: 5))

        // "Erase everything" asks first; "Cancel" keeps everything.
        let erase = app.buttons["settings.erase"]
        walk.reveal(erase)
        erase.tap()
        let question = app.alerts.firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        walk.shoot("erase-question")
        question.buttons[walk.text("Cancel", "Отмена")].tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 5))
        XCTAssertTrue(done.exists)

        // The profiles row: the profiles screen takes the place of the settings.
        let profiles = app.buttons["settings.profiles"]
        walk.reveal(profiles)
        profiles.tap()
        XCTAssertTrue(app.buttons["profiles.done"].waitForExistence(timeout: 5))
        app.buttons["profiles.done"].tap()
        XCTAssertTrue(app.buttons["profiles.done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(walk.homeHero.exists)

        // The language row leaves for Golda's page in the iOS Settings; back, the settings wait.
        walk.tapToolbar("settings")
        let language = app.buttons["settings.language"]
        walk.reveal(language)
        language.tap()
        let preferences = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(preferences.wait(for: .runningForeground, timeout: 10))
        app.activate()
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
    }

    /// "Save a backup" and "Restore" open the system's file panels, and closing a panel leaves the
    /// settings as they were. Skipped where the simulator shows no panel.
    @MainActor
    func testTheBackupRowsOpenTheFilePanels() throws {
        let walk = Walk(shotsName: "backup")
        let app = walk.app
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 30))
        walk.tapToolbar("settings")
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        // The panels' own way out; the settings have none of these.
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Close", "Отменить", "Отмена", "Закрыть"])).firstMatch
        for row in ["settings.export", "settings.import"] {
            let button = app.buttons[row]
            walk.reveal(button)
            button.tap()
            // The panel is up once the settings' "Done" is covered.
            guard waitUntil(timeout: 30, { !done.isHittable }) else { throw XCTSkip("No file panel to drive here.") }
            walk.shoot(row)
            if close.waitForExistence(timeout: 10) {
                close.tap()
            } else {
                // A panel with no button to leave by is pulled down, as a person would.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            }
            XCTAssertTrue(waitUntil(timeout: 10) { done.exists && done.isHittable }, "\(row): back on the settings")
        }
    }

    // MARK: The mic

    /// The first tap asks; "Not now" records nothing, "Agree" starts the recording; the second tap
    /// stops it, the note is booked and announced above the mic, and "Undo" takes it back.
    @MainActor
    func testTheMicAsksRecordsAndUndoes() {
        let walk = Walk(extra: ["-golda.voiceStub=shawarma", "-golda.voiceStub.noConsent"], shotsName: "mic")
        let app = walk.app
        let mic = walk.mic
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 5))
        let before = walk.homeHero.label
        let idle = walk.text("Say it", "Сказать")
        XCTAssertEqual(mic.label, idle)

        mic.tap()
        let notNow = app.buttons["voiceConsent.notNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        walk.shoot("consent")
        notNow.tap()
        XCTAssertTrue(notNow.waitForNonExistence(timeout: 5))
        XCTAssertEqual(mic.label, idle)

        mic.tap()
        app.buttons["voiceConsent.agree"].tap()
        XCTAssertTrue(waitUntil { mic.label == walk.text("Listening. Tap when done", "Слушаю. Нажми, когда закончишь") }, mic.label)
        walk.shoot("recording")
        mic.tap()
        XCTAssertEqual(mic.label, walk.text("Working it out…", "Разбираю…"))
        let toast = walk.staticText(containing: "Шаурма 15 ₾")
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(toast.frame.maxY, mic.frame.minY, "the toast floats above the mic")
        walk.shoot("booked")
        XCTAssertTrue(waitUntil { walk.homeHero.label != before }, "the hero follows the note")
        app.buttons[walk.text("Undo", "Отменить")].tap()
        XCTAssertTrue(waitUntil { walk.homeHero.label == before }, "undo takes the note back")
        XCTAssertEqual(mic.label, idle)
    }
}
