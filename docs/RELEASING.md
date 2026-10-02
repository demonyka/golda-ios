# Releasing

A release is one tag. GitHub Actions builds, signs and publishes the APK.

## One-time setup

The app has to be signed with the same key for every release, or phones cannot
update from one version to the next. Generate a keystore once, or reuse the
one your local builds are already signed with, and keep it and its passwords
out of the repository. Losing it means users have to uninstall, and lose their
data unless they made a backup, to update.

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias golda
```

`keytool` ships with the JDK, but it is rarely on `PATH` on Windows. On macOS or
Linux, run `keytool` with the same arguments.

Add four repository secrets on GitHub (Settings → Secrets and variables →
Actions):

| Secret | Value |
| --- | --- |
| `KEYSTORE_BASE64` | the keystore as base64: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))` in PowerShell, or `base64 -w0 release.jks` |
| `KEYSTORE_PASSWORD` | the store password |
| `KEY_ALIAS` | the key alias, e.g. `golda` |
| `KEY_PASSWORD` | the key password |

These are the same names Alternate and PhoneMic use. The workflow passes them
to Gradle as `GOLDA_STORE_FILE`, `GOLDA_STORE_PASSWORD`, `GOLDA_KEY_ALIAS` and
`GOLDA_KEY_PASSWORD`.

For signed builds on your own machine, put the same values in a
`keystore.properties` file (git-ignored). It can go in either of two places:
next to `settings.gradle.kts`, or in `~/Documents/Golda-secrets/`, a folder
outside the checkout. A relative `storeFile` is read from the same folder as
the properties file.

```properties
storeFile=release.jks
storePassword=...
keyAlias=golda
keyPassword=...
```

With a key, debug and release builds are both signed with it, so one installs
over the other and the app's data survives. Without a key, a local
`assembleRelease` is signed with the debug key. That is fine for trying things
out, but never for publishing.

## Cutting a release

1. Bump `versionCode` and `versionName` in `app/build.gradle.kts`.
2. Add a section for the version to `CHANGELOG.md`. The release notes are
   taken from it, and the workflow stops if the section is missing.
3. Commit, then tag and push:

```bash
git tag -a v0.13.0 -m "0.13.0"
git push origin v0.13.0
```

The tag runs `.github/workflows/release.yml`, which:

1. runs the unit tests;
2. builds the signed APK (the keystore exists on the runner only during that
   job);
3. publishes a GitHub release with `Golda-<version>.apk`, `SHA256SUMS.txt`,
   the CHANGELOG section and a short download guide.

## What signing does not fix

- **Android** warns about apps installed from outside a store, however they
  are signed. The warning is about where the file came from.
- **Builds signed with different keys cannot update each other.** A phone
  with a build signed by another key has to uninstall it first. Export a
  backup in Settings → Data before you do.

## F-Droid and Google Play

Neither is set up. Voice entry depends on Google's Gemini API, a non-free
network service, so on F-Droid the app would carry the *NonFreeNet*
anti-feature. Everything else works without the network.
