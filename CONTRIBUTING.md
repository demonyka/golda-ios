# Contributing

Thanks for taking an interest. Bug reports and pull requests are both welcome.

## Reporting a problem

Open an issue using the bug report form. Please leave out your real balances,
account names and API key. A few made-up numbers that reproduce the problem
are just as useful. For voice entry, the exact phrase you said and what Golda
recorded instead usually pin it down.

## Setting up

Android Studio, or JDK 21 or newer with the Android SDK. The JDK bundled with
Android Studio (`jbr`) works. The app needs a phone or emulator with
Android 16 (API 36).

```bash
./gradlew test lintDebug assembleDebug
```

CI runs exactly these on every push and pull request.

## Trying it without your own data

Debug builds have two shortcuts that fill the app with a made-up person's
accounts, a couple of weeks of spending, goals and a wishlist. Both **erase
everything in the app first**, so never run them on an install that holds
real data:

```bash
adb shell am start -n sh.aminov.golda/.MainActivity --ez golda.demo true     # accounts only
adb shell am start -n sh.aminov.golda/.MainActivity --ez golda.samples true  # accounts, operations, goals, wishlist
```

To keep a real install safe while you develop, add `applicationIdSuffix =
".demo"` to the `debug` build type locally. The debug build then installs as a
separate app with its own data. Don't commit that line.

A voice note can be fed in without speaking: copy a `.wav` or `.ogg` file,
named with its recording time in milliseconds, into the app's `files/voice/`
folder with `run-as`, then start the activity with
`--ez golda.voiceQueue true`.

## Guidelines

- **Match the code around you.** Comments explain *why*, not *what*. Names say
  what things are. The existing files are the style guide.
- **`domain/` stays free of Android.** Money maths, rates, the budget, debts and
  the voice mapper import nothing from `android.*` or Compose. That is what
  lets plain JVM tests cover them. A change there comes with a test.
- **Money is `Long` minor units**, never `Double`. Rates are the only
  floating-point numbers, and they are applied once, at the edge.
- **The model only extracts; the code computes.** The Gemini prompt asks for
  what was said, and nothing more. Conversions, card-charge estimates, hours
  of work and budget shares belong in `domain/`, where they can be tested.
- **Both languages, always.** Every piece of text goes through
  `tr("русский", "English")`. Add both halves in the same change.
- **One gold thing per screen.** Gold marks the one action to take. Anything
  else picked or highlighted is graphite (see `ui/Colors.kt`).
- **Nothing is recorded automatically.** Reading bank notifications or SMS is
  out of scope on purpose. Saying the purchase is what makes you notice it.
- **Room schema changes** need a version bump and a migration (usually an
  `AutoMigration`), and the exported schema in `app/schemas/` must be
  committed with them.

## Release signing

See [docs/RELEASING.md](docs/RELEASING.md). Never commit a keystore, a
`keystore.properties` file or a password.

## Commit messages

Start with a short summary line in the imperative, like "Carry the ruble cost
through ATM withdrawals". If the reason isn't obvious, add a paragraph
explaining why.
