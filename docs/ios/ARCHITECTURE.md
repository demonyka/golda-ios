# Архитектура iOS-версии

Поведение приложения описано в `SPEC.md` и не дублируется здесь. Этот документ — про то, как оно устроено на iOS и чем отличается от Android. Решения и их статус — в `DECISIONS.md`.

## Структура репозитория

```
ios/
  project.yml              XcodeGen: цели, capabilities, схемы
  Golda/                   приложение (SwiftUI)
    App/                   точка входа, сцена, deep links, приём приглашений CloudKit
    UI/                    Home, Accounts, Goals, Insights, Entry, Profiles, Settings, Onboarding, Components
    Theme/                 токены цветов, шрифты, отступы
    Platform/              запись голоса, уведомления, haptics
    Resources/             Assets.xcassets, Localizable.xcstrings, InfoPlist.xcstrings
  GoldaWidgets/            виджет 1×1 и Control Center control
  Packages/
    GoldaCore/             домен; импортирует только Foundation
    GoldaData/             GRDB, репозитории, бэкап, клиент ЦБ, Keychain, голосовая очередь и провайдеры
    GoldaSync/             CloudKit (CKSyncEngine), шаринг
  Tests/                   UI-сценарии (XCUITest); юнит-тесты лежат в пакетах
app/ …                     Android, эталон; удаляется на этапе 7
```

Зависимости в одну сторону: `Golda` → `GoldaSync` → `GoldaData` → `GoldaCore`. Приложение собирает снимок состояния (`AppData`) **активного профиля** из репозитория и отдаёт его экранам, как на Android; логика считается в `GoldaCore`, на экранах её нет.

## Соответствие Android → iOS

| Android | iOS |
|---|---|
| Room | GRDB (SQLite), миграции `DatabaseMigrator` |
| DataStore `Settings` | настройки профиля — таблица `profile`; настройки устройства — UserDefaults (Codable) |
| Android Keystore AES-GCM | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| WorkManager | `UNUserNotificationCenter` + `BGAppRefreshTask` |
| `MediaRecorder` (Opus/AAC) | `AVAudioRecorder`, линейный PCM → WAV 16 кГц mono |
| `HttpURLConnection` + `org.json` | `URLSession` + `Codable` |
| `kotlinx.serialization` | `Codable` |
| `java.time` | `LocalDate`, `YearMonth` в `GoldaCore` (на epoch day), зона передаётся явно |
| `tr("ru", "en")`, `I18n.russian` | String Catalog; домен отдаёт структуры, текст собирает UI |
| `LocaleManager`, переключатель языка | системный язык приложения (Настройки iOS → Golda → Язык) |
| Compose, M3 Expressive | SwiftUI, HIG (см. `DESIGN.md`) |
| Плитка Quick Settings | Control Center control, Action Button |
| Виджет 1×1 | WidgetKit |
| App shortcut | App Shortcuts (App Intents), quick action |
| `POST_NOTIFICATIONS`, `RECORD_AUDIO` | запрос разрешений в момент первой нужды, строки в `InfoPlist.xcstrings` |
| `Demo` по intent-extra | аргумент запуска в debug-сборке |

На Android профилей нет: один человек, один набор данных. Профили — новая сущность iOS-версии (D21).

## Домен (`GoldaCore`)

Переносится из `app/src/main/java/sh/aminov/golda/domain/` по одному файлу вместе с тестами. Домен профилей не знает: его функции получают счета, операции, платежи, цели и `Settings` одного профиля, как получали у Android. `Settings` остаётся составным значением (профильная часть + часть устройства), его собирает слой данных для активного профиля. Тесты Android переносятся без смены ожиданий.

Места, где буквальный перевод даёт другой результат:

- **Округление.** Kotlin `roundToLong()` округляет half-up; Swift `.rounded()` — от нуля. Вся арифметика денег идёт через `Money.roundHalfUp(_ x: Double) -> Int64` (`floor(x + 0.5)`).
- **Формат сумм.** `Fmt` всегда пишет в русском стиле: пробел-разделитель тысяч (неразрывный), запятая, «−» для минуса, «4 210,50 ₽», целые суммы без «,00». Так же и при английском интерфейсе (D13). Форматтеры создаются с фиксированной локалью `ru`, не с текущей.
- **Число знаков валюты.** Берётся из `NumberFormatter` (`currencyCode`, `maximumFractionDigits`) и сверяется тестом с `java.util.Currency` для валют `Currencies.common` и тех, что публикует ЦБ. Резерв — 2 знака, как на Android.
- **Разбор суммы.** `parseMinor` принимает «15», «15,5», «1 500.25» (в том числе неразрывные пробелы), отрицательные и пустые даёт `nil`; округление half-up через `Decimal`.
- **Даты.** `LocalDate` и `YearMonth` — свои значения на epoch day, зеркало `java.time`; границы дня и зона приходят параметром, как `zone` на Android. `Foundation.Date` и `Calendar` остаются на краю (БД, UI).
- **Тексты.** `Debts.advice`, `Goals.waitLabel`, `Category.label`, строка «≈ 2,6 ч работы…» возвращаются данными (enum и числа), UI превращает их в строки через String Catalog с русскими формами множественного числа. Это единственное место, где перенос теста меняет способ проверки.
- **`VoicePrompt`.** Промпт остаётся на русском в точности как на Android, он не локализуется.

## Данные (`GoldaData`)

Все id — UUID (нужно для синхронизации; Int-id Android остаются только в импорте). Деньги — `Int64` минорных единиц, курсы — `Double`. Весь учёт принадлежит профилю: у каждой строки, кроме `rate`, есть `profileId`, он же ключ зоны синхронизации и каскадного удаления.

| Таблица | Поля |
|---|---|
| `profile` | id, name, sort, incomeHourly, hourlyRate, monthlySalary, taxPercent, hoursPerWeek, payday, markup |
| `account` | id, profileId, name, currency, type, groupName?, includeInFree, sort, interestRate?, paymentDay?, paymentMinor?, graceUntil?, reconciledAt? |
| `operation` | id, profileId, type, timestamp, categoryKey?, note, voiceText?, purchaseAmountMinor?, purchaseCurrency?, isEstimate, cbrFrom?, cbrTo?, updatedAt |
| `posting` | id, profileId, operationId, accountId, amountMinor, rubMinor |
| `obligation`, `goal`, `wish` | как на Android, плюс profileId; id — UUID |
| `rate` | code, rubPerUnit, date — общие курсы, не синхронизируются |

Категории встроенные (на Android их нельзя изменить): задаются перечислением с ключом, иконкой и названиями в String Catalog. В операции хранится `categoryKey`.

**Настройки.** Профильная часть (`incomeHourly`, `hourlyRate`, `monthlySalary`, `taxPercent`, `hoursPerWeek`, `payday`, `markup`) лежит в `profile`; `reconciledAt` Android переехал в `account`. Часть устройства — UserDefaults: `onboarded`, активный профиль, `displayCurrencies`, `localCurrency`, `baseCurrency`, `geminiModel`, `reconcileReminder`, а `lastAccountId` и `celebratedGoalId` — по профилям. Ключи API — Keychain. `GoldaCore.Settings` собирается из обеих частей для активного профиля.

**Профили.** Первый запуск создаёт профиль «Личный». Профилей может быть сколько угодно; последний профиль удалить нельзя. Удаление профиля стирает его счета, операции, цели, вишлист и платежи (с подтверждением).

**Записи.** Все изменения идут через репозиторий (актор), в транзакции, и завершаются, даже когда экран ушёл. Удаление операции возвращается «Отменить» теми же id. Правка операции обновляет её проводки на месте (id проводок стабильны), чтобы синхронизация видела правку, а не удаление с созданием.

**Бэкап.** JSON `version: 2` со всеми профилями (Codable, `ignoreUnknownKeys`). Импорт читает `version: 1` Android: Int-id → UUID, `categoryId` → `categoryKey`, всё содержимое попадает в новый профиль «Личный», доход, день зарплаты и наценка уходят в него, настройки устройства — в UserDefaults. Файл читается целиком до изменения данных; битый файл ничего не меняет. Ключи API в бэкап не входят.

**Файлы.** Голосовая очередь — `Application Support/voice/<epochMillis>.wav` с `isExcludedFromBackup`.

## Синхронизация и шаринг (`GoldaSync`)

Цель: общий бюджет с разными людьми — с женой, с другом, с коллегами — без пересечения данных. У участников разные Apple ID. Сервера нет, только iCloud. Единица шаринга — **профиль** (D7, D21).

**Модель CloudKit.**
- **Один профиль — одна зона** в private БД владельца (`profile-<uuid>`), **один `CKShare` на зону** (`CKShare(recordZoneID:)`). Приглашённый видит зону в своей shared БД.
- В зоне записи `Profile` (корень), `Account`, `Operation`, `Posting`, `Obligation`, `Goal`, `Wish`. Ссылки между ними остаются внутри зоны, записи нормализованы, как локальные таблицы.
- Операция уходит вместе с проводками; в записи `Operation` лежит `postingCount`, поэтому приёмник показывает операцию, только когда получил заголовок и все проводки, и терпит их приход в разных пакетах.

**Движок.** Два `CKSyncEngine`: на private и на shared БД. Состояние движков и очередь исходящих изменений хранятся в GRDB. Транспорт стоит за протоколом `SyncTransport`; тесты работают с заглушкой в памяти. Приглашение принимается в `windowScene(_:userDidAcceptCloudKitShareWith:)` (Info.plist: `CKSharingSupported`).

**Что общее, что личное.** Профиль целиком общий для его участников: счета, операции, цели, вишлист, платежи, доход, день зарплаты, наценка. «Можно сегодня» у всех участников профиля считается одинаково по общим данным. На устройстве остаются язык, валюты показа, местная и основная валюта, ключи API, модель Gemini, активный профиль (D16).

**Правила.**
- **Конфликты:** последний записавший побеждает по `updatedAt` на уровне записи. Балансы и рублёвая стоимость сходятся, потому что это суммы проводок; средняя себестоимость при одновременной записи с двух телефонов на один валютный счёт может чуть отличаться от последовательной — стоимость фиксируется на стороне автора.
- **Переводы** только внутри профиля (D22): обе проводки в одной зоне. Деньги между профилями — расход в одном и доход в другом.
- **Права.** Приглашённый по умолчанию читает и пишет (O3).
- **Выход участника или прекращение доступа:** движок сообщает об удалении зоны; приложение удаляет локально профиль и все его данные, отменяет его уведомления, а активным становится другой профиль.
- **Удаление профиля владельцем** удаляет зону: у участников профиль пропадает. Участник «удаляет» профиль, выходя из доступа.
- **Удаление и «Отменить»:** исходящее удаление уходит после окна отмены; отмена до отправки снимает его.
- **Хранилище.** Данные общих профилей лежат в iCloud владельца и расходуют его место.
- **Без iCloud:** приложение работает локально, шаринг недоступен; при включении iCloud существующие профили выгружаются в свои зоны.
- **Автор записи** виден как последний изменивший участник; показ в интерфейсе — после версии 1.

Открыто: передача владения (O2). Допущения про `CKSyncEngine` и shared БД проверяет спайк 5a.

## Голос

`Запись → очередь → провайдер → VoiceMapper → операции → «Записано» + «Отменить»`.

- **Запись** — `AVAudioRecorder`, линейный PCM 16 кГц, mono, 16 бит (WAV, около 32 КБ/с); максимум 60 с; касание короче 0,8 с и тишина (по `averagePower`) ничего не отправляют. Файл называется временем записи.
- **Профиль.** Заметка пишется в профиль, который был активен в момент записи; промпт перечисляет счета этого профиля, валюты показа и местную валюту; подтверждение называет профиль, если их больше одного.
- **Очередь** обрабатывается последовательно (актор) при запуске, при возврате в приложение и после ввода ключа. Без сети или ключа запись ждёт; время операции — время записи.
- **Провайдер** — протокол `VoiceProvider` (`parse(audio, system, model) -> VoiceResult`). В версии 1 один: `GeminiProvider` — тот же запрос и `responseSchema`, что на Android, заголовок `x-goog-api-key`, MIME `audio/wav`, модель задаётся в настройках.
- **Согласие.** До первой отправки — экран с названием провайдера и тем, что именно уходит (правило 5.1.2(i)); отзыв — в настройках. Без согласия сеть не вызывается.
- **Ключ** — в Keychain; настройки хранят только «ключ есть».
- Модель только извлекает; `VoiceMapper` проверяет и считает.

## Вне приложения

- **Уведомления.** Все локальные и по всем профилям, в которых состоит человек: таймеры вишлиста (разовые на `decideAt`), платёж по долгу за 3 дня и в день платежа, льготный период за 7, 1 и 0 дней, сверка по воскресеньям в 19:00 (повтор). В iOS код нельзя запустить в момент показа, поэтому ближайшие уведомления пересчитываются при запуске, при изменении данных и в `BGAppRefreshTask`. Планируется только ближайшее событие каждого долга: у iOS лимит 64 ожидающих уведомления. Нажатие переключает на нужный профиль и открывает нужную вкладку.
- **Точки входа в запись.** Один `StartVoiceNoteIntent` (`openAppWhenRun`) питает Control Center control (iOS 18+), Action Button, виджет 1×1, App Shortcuts и quick action. Запись начинается, когда приложение на переднем плане (так же, как на Android).
- App Group не нужен: виджет и control не показывают данных.

## Сборка, тесты, релиз

- **Проект:** XcodeGen генерирует `Golda.xcodeproj` из `project.yml`. Цели: `Golda`, `GoldaWidgets`, `GoldaUITests`. Пакеты подключены по пути.
- **Capabilities:** iCloud (CloudKit), контейнер `iCloud.com.f4studio.golda`; Push Notifications и фоновый режим `remote-notification` (для тихих пушей CloudKit); Keychain. Info.plist: `CKSharingSupported`, `NSMicrophoneUsageDescription`, URL-схема `golda`. Нужен privacy manifest (UserDefaults, файловые метки).
- **Тесты:** юнит — Swift Testing в пакетах (`swift test` без симулятора); сценарии — XCUITest на симуляторе iPhone 17 (iOS 26.2), приложение поднимается с in-memory БД и отдельными UserDefaults.
- **CI:** `.github/workflows/ios.yml` — macOS-раннер с Xcode 26; метку раннера проверить на этапе 0.
- **Версии:** iOS стартует с `0.1.0`; `1.0.0` — первый релиз в App Store; номер сборки растёт автоматически.
