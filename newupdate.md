# rentmanage — Build & Release Guide

This file tells a human (or an AI) **which APK to build**, **how to build it**, and
**which files must change** for the in-app updater to work correctly.

---

## 1. Canonical build command

```powershell
# from the repo root
cd mobile
flutter build apk --release --target-platform android-arm64
```

- Output: `mobile/build/app/outputs/flutter-apk/app-release.apk`
- Architecture: **arm64-v8a only** (as requested). Do not use `--split-per-abi`
  or a plain `flutter build apk` (that produces a fat APK with more ABIs).
- Copy the result to `releases/rentmanage-arm64-v<version>.apk` in the repo root:

```powershell
Copy-Item mobile\build\app\outputs\flutter-apk\app-release.apk `
          releases\rentmanage-arm64-v1.6.6.apk -Force
```

With the keystore present (`mobile/android/key.properties`), the release build is
signed with it; otherwise it falls back to the debug key.

---

## 2. Files that change on every release

| # | File | Change |
|---|------|--------|
| 1 | `mobile/pubspec.yaml` | Bump **both** `version: X.Y.Z+B`. `X.Y.Z` becomes the APK `versionName` shown as "Current"; `B` becomes `versionCode`, the build number the updater compares. |
| 2 | `releases/rentmanage-arm64-vX.Y.Z.apk` | Add the new APK. |
| 3 | `releases/version.json` | The manifest the app reads: `version`, `build`, `apkUrl`, `message`. `build` must be **greater than the installed build number**, otherwise the app reports "up to date". |

`X.Y.Z` in `pubspec.yaml` must equal `X.Y.Z` in the APK file name and in
`version.json`, otherwise the version labels disagree.

Example `releases/version.json`:

```json
{
  "version": "1.6.6",
  "build": 10,
  "apkUrl": "https://raw.githubusercontent.com/bcsuk999/rentmanage/main/releases/rentmanage-arm64-v1.6.6.apk",
  "message": "Short summary of what changed in this build."
}
```

Commit and push `version.json` and the APK to `main`; the app reads the manifest
from:

```
https://raw.githubusercontent.com/bcsuk999/rentmanage/main/releases/version.json
```

---

## 3. Versioning scheme

- APK file name: `rentmanage-arm64-vX.Y.Z.apk` (e.g. `v1.6.6`).
- Increment `X.Y.Z` monotonically: `… 1.6.4 → 1.6.5 → 1.6.6`.
- Increment the build number `B` on every release (`1.6.5+9 → 1.6.6+10`).
- The updater compares the manifest `build` against the installed `versionCode`
  (via `package_info_plus`). A new release = bump `pubspec.yaml`, name the APK
  with the same version, and raise `build` in `version.json`.

---

## 4. Android configuration that must stay correct

### `mobile/android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```
- Required so the app can hand a downloaded APK to the system package installer.
- This is a **special access** ("Install unknown apps"), not a runtime dialog.
  Android shows the allow prompt when the installer opens.
- **Storage permission is NOT needed** — the APK is written to the app's own
  temporary directory.

### `mobile/android/app/build.gradle.kts`
```kotlin
android {
    compileSdk = 37   // permission_handler_android requires SDK 37
}
```
- If Gradle fails with `Failed to find target with hash string 'android-37'`, the
  installed platform folder is named `android-37.0` while AGP 8.x expects
  `android-37`. Fix by mirroring the SDK platform:
  `…\Android\Sdk\platforms\android-37.0` → `…\platforms\android-37` and set
  `AndroidVersion.ApiLevel=37` in its `source.properties`.

---

## 5. Updater behaviour (`mobile/lib/update_service.dart`, `app_update_page.dart`)

- **Launch check**: every app start quietly fetches `version.json`. If its
  `build` is newer than the installed build, a prompt shows the version jump and
  the release message; **Update now** opens the App Updates page. Network
  failures stay silent.
- **Check for update**: fetches the manifest with a cache-busting query
  (`?v=<installed build>`), parses `version`, `build`, `apkUrl` and `message`.
- **What's new**: the manifest `message` is shown on the update page and in the
  launch prompt.
- **Download & Install**:
  1. Streams the APK from `apkUrl` to the app temporary directory, showing live
     progress, download speed and size.
  2. Opens the APK with `open_filex`; Android's installer handles the rest.
- Buttons mute while a check/download runs; there is no spinner on them.
- There is **no** "Open in browser instead" option.

---

## 6. Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| App says "up to date" but a new APK exists | `build` in `version.json` is not greater than the installed build number. |
| App still shows the old version after installing | `pubspec.yaml` `version:`/build was not bumped, or the APK was not rebuilt. |
| Update check fails | `releases/version.json` is missing/invalid on `main`, or `apkUrl` points to a file that is not pushed. |
| APK won't install ("unknown apps" blocked) | `REQUEST_INSTALL_PACKAGES` missing in the manifest, or the user hasn't enabled "Install unknown apps" for Rent Manager. |
| `Failed to find target with hash string 'android-37'` | SDK platform folder mismatch — see section 4. |
| Download says "Starting download…" forever | `apkUrl` is unreachable or the host does not return a content length. |
