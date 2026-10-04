import Foundation

/// One thing said in a voice note, as the model extracted it. Nothing here is computed.
public struct VoiceItem: Equatable, Sendable {
    public var intent: String
    public var amount: String?
    public var currency: String?
    public var note: String
    public var category: String?
    /// A position in the account list the prompt showed ("1" is the first), not a database id.
    public var accountId: String?
    public var toAccountId: String?
    public var toAmount: String?
    public var date: String?

    public init(
        intent: String, amount: String? = nil, currency: String? = nil, note: String = "", category: String? = nil,
        accountId: String? = nil, toAccountId: String? = nil, toAmount: String? = nil, date: String? = nil
    ) {
        self.intent = intent
        self.amount = amount
        self.currency = currency
        self.note = note
        self.category = category
        self.accountId = accountId
        self.toAccountId = toAccountId
        self.toAmount = toAmount
        self.date = date
    }
}

public struct VoiceResult: Equatable, Sendable {
    public var transcript: String
    public var items: [VoiceItem]

    public init(transcript: String, items: [VoiceItem]) {
        self.transcript = transcript
        self.items = items
    }
}

/// "Хочу купить бургер за 50 $": not spent yet. An empty [title] means the speaker named nothing;
/// the screen then writes its own "Purchase".
public struct Consider: Equatable, Sendable {
    public var title: String
    public var amountMinor: Int64
    public var currency: String

    public init(title: String, amountMinor: Int64, currency: String) {
        self.title = title
        self.amountMinor = amountMinor
        self.currency = currency
    }
}

public enum VoiceAction: Equatable, Sendable {
    case record(Draft)
    case consider(Consider)
    case notUnderstood(String)
}

public enum VoicePrompt {
    /// JSON schema the model must answer with.
    public static let schema = """
    {"type":"object","properties":{
      "transcript":{"type":"string"},
      "items":{"type":"array","items":{"type":"object","properties":{
        "intent":{"type":"string","enum":["expense","income","transfer","consider","unknown"]},
        "amount":{"type":"string","nullable":true},
        "currency":{"type":"string","nullable":true},
        "note":{"type":"string"},
        "category":{"type":"string","nullable":true},
        "account_id":{"type":"string","nullable":true},
        "to_account_id":{"type":"string","nullable":true},
        "to_amount":{"type":"string","nullable":true},
        "date":{"type":"string","nullable":true}
      },"required":["intent","note"]}}
    },"required":["transcript","items"]}
    """

    /// The system prompt. [accounts] must be the same list, in the same order, that
    /// `VoiceMapper.actions` later receives: the model answers with positions in it ("3"), which
    /// are short and unambiguous where a UUID is neither.
    public static func system(accounts: [Account], categories: [Category], settings: Settings, today: LocalDate) -> String {
        let accountLines = accounts.enumerated()
            .map { "- \($0.offset + 1): \($0.element.name), \($0.element.currency), \($0.element.type.rawValue.lowercased())" }
            .joined(separator: "\n")
        func cats(_ kind: CategoryKind) -> String {
            categories.filter { $0.kind == kind }.map { "\($0.key) (\($0.name))" }.joined(separator: ", ")
        }
        return """
        Ты разбираешь голосовые записи о личных деньгах в JSON. Ничего не считай и не конвертируй, только извлекай сказанное.
        Сегодня \(today) (\(today.dayOfWeek.russianName)). Местная валюта: \(settings.localCurrency). Валюты пользователя: \(settings.displayCurrencies.joined(separator: ", ")).

        Счета (номер: название, валюта, тип):
        \(accountLines)

        Категории расходов: \(cats(.expense)).
        Категории доходов: \(cats(.income)).

        Правила:
        - Каждая трата, доход или перевод — отдельный элемент items. «Кофе 8 и круассан 6» — два расхода.
        - Если человек оговорился и поправился («15 бат, ой, лари»), бери исправленное.
        - «Хочу купить», «стоит ли брать», «думаю купить» — intent consider.
        - Перевод между своими счетами или снятие наличных — transfer: account_id откуда, to_account_id куда, to_amount — сколько пришло, если сказано.
        - amount и to_amount — число строкой с точкой: "15", "1500.5". Валюта — код ISO: лари GEL, бат THB, доллар/бакс USD, рубль RUB, евро EUR. Не названа — null.
        - account_id только из списка выше (номер счёта строкой) и только если счёт явно назван или однозначно следует из сказанного («наличкой», «с кредитки»), иначе null.
        - category — ключ из списка или null. note — коротко, что купил, с маленькой буквы.
        - date в формате YYYY-MM-DD, только если назван день («вчера», «в понедельник»), иначе null.
        - Если не про деньги или не разобрать — один элемент с intent unknown.
        """
    }
}

public enum VoiceMapper {
    /// [accounts] is the list the prompt was built from, in the same order. [unnamedPurchase] is the
    /// localized title for a "хочу купить" with no name.
    public static func actions(
        _ result: VoiceResult,
        accounts: [Account],
        categories: [Category],
        settings: Settings,
        rates: Rates,
        recordedAt: Int64,
        zone: TimeZone,
        unnamedPurchase: String = "Purchase"
    ) -> [VoiceAction] {
        if result.items.isEmpty { return [.notUnderstood(result.transcript)] }
        return result.items.map {
            action($0, result.transcript, accounts, categories, settings, rates, recordedAt, zone, unnamedPurchase)
        }
    }

    private static func action(
        _ item: VoiceItem,
        _ transcript: String,
        _ accounts: [Account],
        _ categories: [Category],
        _ settings: Settings,
        _ rates: Rates,
        _ recordedAt: Int64,
        _ zone: TimeZone,
        _ unnamedPurchase: String
    ) -> VoiceAction {
        func named(_ position: String?) -> Account? {
            guard let position, let n = Int(position), accounts.indices.contains(n - 1) else { return nil }
            return accounts[n - 1]
        }
        let said = item.currency.map { $0.uppercased() }.flatMap { $0.count == 3 ? $0 : nil }
        let currency = said ?? unsaidCurrency(item, named, settings.localCurrency)
        let amount = item.amount.flatMap { Fmt.parseMinor($0, currency) }.flatMap { $0 > 0 ? $0 : nil }
        let trimmed = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        let timestamp = timestamp(item.date, recordedAt, zone)
        let categoryKey = item.category.flatMap { key in categories.first { $0.key == key }?.key }
        let lost = VoiceAction.notUnderstood(transcript)

        switch item.intent {
        case "consider":
            guard let amount else { return lost }
            return .consider(Consider(title: note.isEmpty ? unnamedPurchase : note, amountMinor: amount, currency: currency))

        case "expense":
            guard let amount, let account = named(item.accountId) ?? pick(accounts, currency, settings) else { return lost }
            if account.currency == currency {
                return .record(Draft(
                    type: .expense, timestamp: timestamp, accountId: account.id, amountMinor: amount,
                    categoryKey: categoryKey, note: note, voiceText: transcript
                ))
            }
            guard let charged = rates.cardCharge(amount, purchase: currency, account: account.currency) else { return lost }
            return .record(Draft(
                type: .expense, timestamp: timestamp, accountId: account.id, amountMinor: charged,
                categoryKey: categoryKey, note: note, purchaseAmountMinor: amount, purchaseCurrency: currency,
                isEstimate: true, voiceText: transcript
            ))

        case "income":
            guard let amount, let account = named(item.accountId) ?? pick(accounts, currency, settings) else { return lost }
            let credited = account.currency == currency ? amount : rates.convert(amount, from: currency, to: account.currency)
            guard let credited else { return lost }
            return .record(Draft(
                type: .income, timestamp: timestamp, accountId: account.id, amountMinor: credited,
                categoryKey: categoryKey, note: note, voiceText: transcript
            ))

        case "transfer":
            guard let from = named(item.accountId) ?? pick(accounts, currency, settings),
                  let to = named(item.toAccountId), to.id != from.id
            else { return lost }
            let said = item.toAmount.flatMap { Fmt.parseMinor($0, to.currency) }.flatMap { $0 > 0 ? $0 : nil }
            let sent: Int64?
            if let amount {
                sent = from.currency == currency ? amount : rates.convert(amount, from: currency, to: from.currency)
            } else if let said {
                // Only what arrived was given (D46): what left the source follows from it.
                sent = to.currency == from.currency ? said : rates.convert(said, from: to.currency, to: from.currency)
            } else {
                sent = nil
            }
            guard let sent else { return lost }
            let received = said ?? (to.currency == from.currency ? sent : rates.convert(sent, from: from.currency, to: to.currency))
            guard let received else { return lost }
            // One side of a transfer between currencies is the bank's to say: the received one when
            // only the sent amount was given, the sent one when only the received amount was.
            let guessed = to.currency != from.currency && (item.toAmount == nil || amount == nil)
            return .record(Draft(
                type: .transfer, timestamp: timestamp, accountId: from.id, amountMinor: sent, toAccountId: to.id,
                toAmountMinor: received, note: note, isEstimate: guessed, voiceText: transcript
            ))

        default:
            return lost
        }
    }

    /// The expense for a purchase decided on after a `.consider`.
    public static func buy(_ consider: Consider, accounts: [Account], settings: Settings, rates: Rates, now: Int64) -> Draft? {
        guard let account = pick(accounts, consider.currency, settings) else { return nil }
        if account.currency == consider.currency {
            return Draft(type: .expense, timestamp: now, accountId: account.id, amountMinor: consider.amountMinor, note: consider.title)
        }
        guard let charged = rates.cardCharge(consider.amountMinor, purchase: consider.currency, account: account.currency) else { return nil }
        return Draft(
            type: .expense, timestamp: now, accountId: account.id, amountMinor: charged, note: consider.title,
            purchaseAmountMinor: consider.amountMinor, purchaseCurrency: consider.currency, isEstimate: true
        )
    }

    /// The account a phrase most likely means when it names none: the last one used if it is in the
    /// right currency, else a free-money account in that currency, else the last one used anyway
    /// (the purchase is then converted).
    public static func pick(_ accounts: [Account], _ currency: String, _ settings: Settings) -> Account? {
        let last = settings.lastAccountId.flatMap { id in accounts.first { $0.id == id } }
        let spendable = accounts.filter { $0.includeInFree || $0.type == .credit }
        if let last, last.currency == currency { return last }
        return spendable.first { $0.currency == currency } ?? last ?? spendable.first ?? accounts.first
    }

    /// The currency of an amount said without one (D44). A purchase is priced in the local money,
    /// whatever card pays for it. Money moved between the person's own accounts, or coming into a
    /// named one, is counted in those accounts' money: «перевёл с карты на накопительный восемьдесят
    /// тысяч» between two ruble accounts is rubles, not lari. Accounts in different currencies keep
    /// the local money when it is one of them (a cash machine gives local money), else the source's.
    private static func unsaidCurrency(_ item: VoiceItem, _ named: (String?) -> Account?, _ local: String) -> String {
        let accounts: [Account] = switch item.intent {
        case "transfer": [named(item.accountId), named(item.toAccountId)].compactMap { $0 }
        case "income": [named(item.accountId)].compactMap { $0 }
        default: []
        }
        let currencies = accounts.map(\.currency)
        guard let first = currencies.first else { return local }
        if currencies.allSatisfy({ $0 == first }) { return first }
        return currencies.contains(local) ? local : first
    }

    private static func timestamp(_ date: String?, _ recordedAt: Int64, _ zone: TimeZone) -> Int64 {
        guard let day = date.flatMap({ LocalDate(iso: $0) }) else { return recordedAt }
        let recordedDay = Ledger.localDate(recordedAt, zone)
        return day >= recordedDay ? recordedAt : day.atTimeMillis(hour: 12, in: zone)
    }
}
