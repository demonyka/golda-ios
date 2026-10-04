"""Publishes (or updates) Golda's privacy policy and support pages on telegra.ph.

The account token lives in the login Keychain (service `golda.telegraph`), never in the repository;
the pages' paths are in pages.json next to this file, so a re-run edits the same pages.
"""
import json, subprocess, sys, urllib.parse, urllib.request
from pathlib import Path

HERE = Path(__file__).parent
API = "https://api.telegra.ph/"
ISSUES = "https://github.com/demonyka/golda-ios/issues"
REPO = "https://github.com/demonyka/golda-ios"


def call(method, **params):
    data = urllib.parse.urlencode({k: json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else v for k, v in params.items()}).encode()
    with urllib.request.urlopen(API + method, data) as r:
        answer = json.load(r)
    if not answer.get("ok"):
        sys.exit(f"{method}: {answer}")
    return answer["result"]


def token():
    found = subprocess.run(["security", "find-generic-password", "-s", "golda.telegraph", "-w"], capture_output=True, text=True)
    if found.returncode == 0:
        return found.stdout.strip()
    account = call("createAccount", short_name="Golda", author_name="Golda", author_url=REPO)
    subprocess.run(["security", "add-generic-password", "-s", "golda.telegraph", "-a", "telegraph", "-w", account["access_token"]], check=True)
    return account["access_token"]


def h(text): return {"tag": "h3", "children": [text]}
def h4(text): return {"tag": "h4", "children": [text]}
def p(*parts): return {"tag": "p", "children": list(parts)}
def a(text, href): return {"tag": "a", "attrs": {"href": href}, "children": [text]}
def ul(*items): return {"tag": "ul", "children": [{"tag": "li", "children": [i] if isinstance(i, str) else list(i)} for i in items]}
def hr(): return {"tag": "hr"}


PRIVACY = [
    p("Действует с 4 октября 2026 года. English version below."),
    h("Коротко"),
    p("У Golda нет своих серверов, аккаунтов, рекламы и аналитики. Ваши счета, операции и цели хранятся на вашем iPhone и, если вы включили iCloud, в вашем личном iCloud. Разработчик их не видит."),
    h("Что остаётся на телефоне"),
    p("Счета, операции, цели, вишлист, платежи, доход и настройки хранятся в базе данных приложения на iPhone. Ключ Gemini хранится в Связке ключей iPhone, только на этом устройстве, и не попадает ни в резервные копии, ни в синхронизацию."),
    h("Голосовой ввод"),
    p("Golda не распознаёт речь сама. Если вы добавили свой ключ Google Gemini и согласились на отправку голоса, запись, которую вы делаете после нажатия на микрофон, отправляется напрямую в Google Gemini с вашим ключом — вместе с названиями и валютами ваших счетов и списком категорий, чтобы модель поняла, чем вы платили. Остатки, операции и другие данные не отправляются. Запрос идёт с телефона в Google без посредников; Google обрабатывает его по ",
      a("условиям Gemini API", "https://ai.google.dev/gemini-api/terms"), ". На телефоне запись удаляется, как только операция сохранена. Согласие можно отозвать в Настройках; без него голос выключен, а ввод руками работает всегда."),
    h("Синхронизация и общий профиль"),
    p("Синхронизация идёт через Apple iCloud (CloudKit): данные профиля лежат в вашей личной базе iCloud, зашифрованные поля недоступны ни Apple, ни разработчику. Если вы пригласили человека в профиль, ему становятся видны данные этого профиля — и только его. Доступ можно закрыть в любой момент."),
    h("Курсы валют"),
    p("Чтобы пересчитывать суммы, приложение загружает общедоступные курсы: официальные курсы ЦБ РФ (cbr-xml-daily.ru) и курсы других валют (currency-api через cdn.jsdelivr.net и pages.dev). Эти запросы не содержат ваших данных."),
    h("Уведомления и виджеты"),
    p("Напоминания планируются на самом телефоне. Виджеты получают от приложения только то, что показывают («Можно сегодня»), через общее хранилище на этом же iPhone."),
    h("Резервные копии"),
    p("Файл резервной копии создаётся только по вашей команде и сохраняется туда, куда вы его отправите. Ключ Gemini в него не входит."),
    h("Дети"),
    p("Приложение не предназначено для детей младше 13 лет и не собирает о них данных."),
    h("Удаление данных"),
    p("«Стереть всё» в Настройках удаляет данные с телефона. Удаление приложения удаляет локальные данные; данные в iCloud можно удалить в Настройках iOS → [ваше имя] → iCloud → Управлять хранилищем → Golda."),
    h("Изменения и контакты"),
    p("Об изменениях политики будет сказано на этой странице. Вопросы: ", a(ISSUES, ISSUES), "."),
    hr(),
    h("Privacy Policy (English)"),
    p("Effective October 4, 2026."),
    p("Golda has no servers, accounts, ads or analytics of its own. Your accounts, transactions and goals stay on your iPhone and, if you turn iCloud on, in your own iCloud. The developer cannot see them."),
    p("Voice input: Golda does not recognise speech itself. If you add your own Google Gemini key and agree, the recording you make after tapping the mic is sent straight to Google Gemini with your key, together with the names and currencies of your accounts and the category list, so the model can tell what you paid with. Balances and other records are not sent. Google handles the request under the ",
      a("Gemini API terms", "https://ai.google.dev/gemini-api/terms"), ". The recording is deleted from the phone as soon as the transaction is saved. You can withdraw consent in Settings; typing always works."),
    p("Sync goes through Apple iCloud (CloudKit), in your private database, with encrypted fields. People you invite to a profile see that profile only; you can stop sharing at any time."),
    p("Exchange rates are downloaded from public sources (the Bank of Russia via cbr-xml-daily.ru, currency-api via cdn.jsdelivr.net and pages.dev); these requests carry none of your data. Reminders are scheduled on the phone. Backups are made only when you ask, and never include the Gemini key."),
    p("The app is not directed at children under 13. Erase everything in Settings removes the data from the phone; iCloud data can be removed in iOS Settings → your name → iCloud → Manage Storage → Golda. Questions: ", a(ISSUES, ISSUES), "."),
]

SUPPORT = [
    p("Golda — учёт денег, где трату можно просто сказать. English below."),
    h("Частые вопросы"),
    h4("Как включить голосовой ввод?"),
    p("Нужен свой ключ Google Gemini: создайте его в ", a("Google AI Studio", "https://aistudio.google.com/apikey"), " и вставьте в Настройки → Голос. Затем нажмите на микрофон и скажите, например, «шаурма пятнадцать лари»."),
    h4("Голос не работает в моей стране"),
    p("Gemini доступен не во всех странах. Записи не теряются: они ждут, пока запрос станет возможен. Ввод руками через «+» работает всегда."),
    h4("Как вести общий бюджет с семьёй?"),
    p("Управление профилями → выберите профиль → «Пригласить…» и отправьте приглашение через AirDrop или Сообщения. У обоих должен быть включён iCloud."),
    h4("Как перенести данные с Android-версии Golda?"),
    p("В Android-версии сохраните резервную копию, затем в Golda для iPhone откройте Настройки → Данные → «Восстановить» и выберите файл."),
    h4("Что такое «Можно сегодня»?"),
    p("Сколько можно потратить сегодня, чтобы денег хватило до зарплаты с учётом обязательных платежей. Число пересчитывается после каждой траты."),
    h("Связаться"),
    p("Ошибки и предложения: ", a(ISSUES, ISSUES), ". Политика конфиденциальности: ", a("telegra.ph", "PRIVACY_URL"), "."),
    hr(),
    h("Support (English)"),
    p("Voice input needs your own Google Gemini key: create one in ", a("Google AI Studio", "https://aistudio.google.com/apikey"),
      " and paste it in Settings → Voice. To share a budget, open Manage profiles, pick a profile and tap Invite…; both people need iCloud on. To move from Golda for Android, save a backup there and restore it in Settings → Data → Restore."),
    p("Bugs and ideas: ", a(ISSUES, ISSUES), "."),
]


def main():
    t = token()
    pages_file = HERE / "pages.json"
    pages = json.loads(pages_file.read_text()) if pages_file.exists() else {}
    def publish(key, title, content):
        if key in pages:
            return call("editPage/" + pages[key], access_token=t, title=title, content=content, author_name="Golda", author_url=REPO)["url"]
        page = call("createPage", access_token=t, title=title, content=content, author_name="Golda", author_url=REPO)
        pages[key] = page["path"]
        return page["url"]
    privacy = publish("privacy", "Golda — политика конфиденциальности", PRIVACY)
    support_content = json.loads(json.dumps(SUPPORT).replace("PRIVACY_URL", privacy))
    support = publish("support", "Golda — поддержка", support_content)
    pages_file.write_text(json.dumps(pages, indent=2) + "\n")
    print(privacy)
    print(support)


main()
