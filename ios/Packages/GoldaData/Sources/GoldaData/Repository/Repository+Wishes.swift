import Foundation
import GoldaCore

// Monthly payments, goals and the wishlist: the data side of Android's `Wishes`. Reminders are
// scheduled by the app from the stored wishes, not here.
extension Repository {
    // MARK: Obligations

    /// [createdAt] is the payment's place in the creation order, which lists the payments of one day.
    /// Nil keeps a stored payment's place and puts a new one after the others; undo of
    /// `deleteObligation` passes the place it had.
    public func saveObligation(_ obligation: Obligation, profileId: UUID, createdAt: Int64? = nil) async throws {
        try await write { store in
            if let createdAt {
                try store.restore(obligation, createdAt: createdAt, profileId: profileId)
            } else {
                try store.save(obligation, profileId: profileId)
            }
        }
    }

    /// Deletes the payment and returns what "Отменить" needs to bring it back to its place; nil when
    /// the profile has no such payment.
    @discardableResult
    public func deleteObligation(_ id: UUID, profileId: UUID) async throws -> DeletedObligation? {
        try await write { store in
            guard let obligation = try store.obligation(id, profileId: profileId),
                  let createdAt = try store.createdAt(ofObligation: id, profileId: profileId)
            else { return nil }
            try store.deleteObligation(id, profileId: profileId)
            return DeletedObligation(obligation: obligation, createdAt: createdAt)
        }
    }

    // MARK: Goals

    /// Saves the goal and keeps exactly one main goal: a goal saved as main takes over, and when
    /// none is left the oldest becomes main.
    ///
    /// [createdAt] is the goal's place in the creation order, which says which goal is the oldest.
    /// Nil keeps a stored goal's place and puts a new one after the others; undo of `deleteGoal`
    /// passes the place it had.
    public func saveGoal(_ goal: Goal, profileId: UUID, createdAt: Int64? = nil) async throws {
        try await write { store in
            if let createdAt {
                try store.restore(goal, createdAt: createdAt, profileId: profileId)
            } else {
                try store.save(goal, profileId: profileId)
            }
            if goal.isMain {
                for var other in try store.goals(profileId: profileId) where other.isMain && other.id != goal.id {
                    other.isMain = false
                    try store.save(other, profileId: profileId)
                }
            }
            try Self.electMainGoal(store, profileId: profileId)
        }
    }

    /// Deletes the goal; when it was the main one, the oldest left takes its place. Returns what
    /// "Отменить" needs to bring it back to its place; nil when the profile has no such goal.
    @discardableResult
    public func deleteGoal(_ id: UUID, profileId: UUID) async throws -> DeletedGoal? {
        try await write { store in
            let goal = try store.goal(id, profileId: profileId)
            let createdAt = try store.createdAt(ofGoal: id, profileId: profileId)
            try store.deleteGoal(id, profileId: profileId)
            try Self.electMainGoal(store, profileId: profileId)
            guard let goal, let createdAt else { return nil }
            return DeletedGoal(goal: goal, createdAt: createdAt)
        }
    }

    private static func electMainGoal(_ store: Store, profileId: UUID) throws {
        // Main first, then oldest: with no main goal the first one is the oldest.
        let goals = try store.goals(profileId: profileId)
        guard !goals.contains(where: \.isMain), var oldest = goals.first else { return }
        oldest.isMain = true
        try store.save(oldest, profileId: profileId)
    }

    // MARK: Wishes

    /// "Подумаю": the purchase waits on the list until its thinking time is up (`Goals.waitHours`).
    /// Returns the stored wish; its reminder is due at `decideAt`.
    @discardableResult
    public func think(_ consider: Consider, profileId: UUID) async throws -> Wish {
        let now = clock()
        let context = try await budgetContext(profileId: profileId, now: now)
        let rub = Goals.rubOf(consider.amountMinor, consider.currency, context.rates)
        let hours = Goals.waitHours(rub, context.settings, YearMonth(from: context.day))
        let wish = Wish(
            title: consider.title, amountMinor: consider.amountMinor, currency: consider.currency, createdAt: now,
            decideAt: now + hours * 3_600_000
        )
        try await write { try $0.save(wish, profileId: profileId) }
        return wish
    }

    /// "Не беру": the refusal is remembered (the waiting [wishId], or a new one decided on the spot,
    /// since "Не купил" sums them all) and the money goes towards the main goal.
    @discardableResult
    public func skip(_ consider: Consider, wishId: UUID? = nil, profileId: UUID) async throws -> SkipOutcome {
        let now = clock()
        let device = deviceSettings.current
        let zone = zone()
        return try await write { store in
            let context = try Self.budgetContext(store, profileId: profileId, device: device, now: now, zone: zone)
            let waiting = try wishId.flatMap { try store.wish($0, profileId: profileId) }
            var wish = waiting ?? Wish(
                title: consider.title, amountMinor: consider.amountMinor, currency: consider.currency, createdAt: now,
                decideAt: now
            )
            wish.status = .skipped
            wish.decidedAt = now
            try store.save(wish, profileId: profileId)

            guard var goal = context.mainGoal else { return SkipOutcome(wish: wish, goal: nil, addedMinor: nil) }
            let rub = Goals.rubOf(consider.amountMinor, consider.currency, context.rates)
            let added = Goals.minorOfRub(rub, goal.currency, context.rates)
            // Held at Int64.max: savings already that big (an old backup) must not trap (D59).
            goal.savedMinor = Money.add(goal.savedMinor, added)
            try store.save(goal, profileId: profileId)
            return SkipOutcome(wish: wish, goal: goal, addedMinor: added)
        }
    }

    /// "Беру": records the expense (`VoiceMapper.buy` picks the account) and marks [wishId] bought.
    /// Returns the operation id, or nil when there is no account to pay from.
    @discardableResult
    public func buy(_ consider: Consider, wishId: UUID? = nil, profileId: UUID) async throws -> UUID? {
        let now = clock()
        let device = deviceSettings.current
        let draft = try await write { store -> Draft? in
            guard let profile = try store.profile(profileId) else { throw RepositoryError.unknownProfile(profileId) }
            let settings = Settings(profile: profile.settings, device: device, profileId: profileId)
            let rates = try Self.rates(store, markup: profile.settings.markup)
            guard let draft = VoiceMapper.buy(
                consider, accounts: try store.accounts(profileId: profileId), settings: settings, rates: rates, now: now
            ) else { return nil }
            var booked = draft
            booked.id = try Self.book(draft, profileId: profileId, in: store, at: now)
            if let wishId { try Self.decide(wishId, .bought, profileId: profileId, in: store, at: now) }
            return booked
        }
        guard let draft else { return nil }
        deviceSettings.update { $0.lastAccountId[profileId] = draft.accountId }
        return draft.id
    }

    /// A waiting wish bought after all, through the ordinary expense form.
    public func bought(wishId: UUID, profileId: UUID) async throws {
        let now = clock()
        try await write { try Self.decide(wishId, .bought, profileId: profileId, in: $0, at: now) }
    }

    /// Deletes the wish and returns it for "Отменить"; nil when the profile has no such wish.
    @discardableResult
    public func deleteWish(_ id: UUID, profileId: UUID) async throws -> Wish? {
        try await write { store in
            guard let wish = try store.wish(id, profileId: profileId) else { return nil }
            try store.deleteWish(id, profileId: profileId)
            return wish
        }
    }

    /// Undo of `deleteWish`: the wish comes back as it was.
    public func restoreWish(_ wish: Wish, profileId: UUID) async throws {
        try await write { try $0.save(wish, profileId: profileId) }
    }

    private static func decide(_ wishId: UUID, _ status: WishStatus, profileId: UUID, in store: Store, at now: Int64) throws {
        guard var wish = try store.wish(wishId, profileId: profileId) else { return }
        wish.status = status
        wish.decidedAt = now
        try store.save(wish, profileId: profileId)
    }

    // MARK: Read models

    /// What a recorded expense cost in work and what is left for today; nil unless [operationId]
    /// is an expense of the profile.
    public func impact(operationId: UUID, profileId: UUID) async throws -> Impact? {
        let now = clock()
        let device = deviceSettings.current
        let zone = zone()
        return try await database.read { store in
            guard let full = try store.operation(operationId, profileId: profileId), full.op.type == .expense else { return nil }
            let context = try Self.budgetContext(store, profileId: profileId, device: device, now: now, zone: zone)
            let cost = -full.postings.moneySum(\.rubMinor)
            let hourNet = context.settings.hourNet
            return Impact(
                costRub: cost,
                hoursOfWork: hourNet > 0 ? Double(cost) / 100.0 / hourNet : nil,
                leftTodayRub: context.today.leftTodayRub
            )
        }
    }

    /// The numbers the "хочу купить" card shows, the wait "Подумаю" would take included.
    public func consider(_ consider: Consider, profileId: UUID) async throws -> Facts {
        let context = try await budgetContext(profileId: profileId, now: clock())
        let rub = Goals.rubOf(consider.amountMinor, consider.currency, context.rates)
        var facts = Goals.facts(
            item: consider.title, rubMinor: rub, settings: context.settings, perDayRub: context.today.perDayRub,
            mainGoal: context.mainGoal, rates: context.rates
        )
        facts.waitHours = Goals.waitHours(rub, context.settings, YearMonth(from: context.day))
        return facts
    }

    // MARK: Budget context

    /// What "хочу купить" and the comment after an expense are weighed against.
    struct BudgetContext: Sendable {
        var settings: Settings
        var rates: Rates
        var day: LocalDate
        var today: Today
        var mainGoal: Goal?
    }

    private func budgetContext(profileId: UUID, now: Int64) async throws -> BudgetContext {
        let device = deviceSettings.current
        let zone = zone()
        return try await database.read { store in
            try Self.budgetContext(store, profileId: profileId, device: device, now: now, zone: zone)
        }
    }

    /// Android's `Wishes.snapshot`: today's budget of the profile with its payments set aside.
    private static func budgetContext(
        _ store: Store, profileId: UUID, device: DeviceSettings, now: Int64, zone: TimeZone
    ) throws -> BudgetContext {
        guard let profile = try store.profile(profileId) else { throw RepositoryError.unknownProfile(profileId) }
        let settings = Settings(profile: profile.settings, device: device, profileId: profileId)
        let rates = try rates(store, markup: profile.settings.markup)
        let accounts = try store.accounts(profileId: profileId)
        let day = LocalDate(epochMillis: now, in: zone)
        let today = Budget.today(
            states: Ledger.states(accounts, try store.postings(profileId: profileId)),
            operations: try store.operations(profileId: profileId, since: day.startOfDayMillis(in: zone)),
            settings: settings,
            today: day,
            zone: zone,
            obligations: try store.obligations(profileId: profileId) + Debts.obligations(accounts),
            rates: rates
        )
        let mainGoal = try store.goals(profileId: profileId).first(where: \.isMain)
        return BudgetContext(settings: settings, rates: rates, day: day, today: today, mainGoal: mainGoal)
    }
}
