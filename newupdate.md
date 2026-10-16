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
          releases\rentmanage-arm64-v1.6.1.apk -Force
```

With the keystore present (`mobile/android/key.properties`), the release build is
signed with it; otherwise it falls back to the debug key.

---

## 2. Files that change on every release

| # | File | Change |
|---|------|--------|
| 1 | `mobile/pubspec.yaml` | Bump `version: X.Y.Z+B`. **This becomes the APK `versionName`, which `package_info_plus` reports as the "Installed" version.** If you forget this, the app keeps showing the OLD version number after installing the new APK. |
| 2 | `releases/rentmanage-arm64-vX.Y.Z.apk` | Add the new APK. The updater picks the **highest-named** `.apk` in this folder. |
| 3 | GitHub Release (optional) | If a GitHub *Release* with an `.apk` asset exists, it takes precedence over the `releases/` folder. |

`X.Y.Z` in `pubspec.yaml` **must equal** `X.Y.Z` in the APK file name, otherwise the
"Update available / up to date" comparison and the "Installed:" label disagree.

---

## 3. Versioning scheme

- APK file name: `rentmanage-arm64-vX.Y.Z.apk` (e.g. `v1.6.1`).
- Increment `X.Y.Z` monotonically: `… 1.5.0 → 1.6.0 → 1.6.1`.
- The updater compares the newest APK name against the installed `versionName`
  with a numeric `X.Y.Z` compare (`AppUpdatePage._compare`).
- So: new release = bump `pubspec.yaml` **and** name the APK with the same version.

---

## 4. Android configuration that must stay correct

### `mobile/android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```
- Required so the app can hand a downloaded APK to the system package installer.
- This is a **special access** ("Install unknown apps"), not a runtime dialog.
  It is requested in-app via `Permission.requestInstallPackages`.
- **Storage permission is NOT needed** — the APK is written to the app's own
  external directory.

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

## 5. Updater behaviour (`mobile/lib/app_update_page.dart`)

- **Check for update**: reads the GitHub *latest Release* `.apk` asset; if none,
  falls back to the highest `rentmanage-arm64-vX.Y.Z.apk` under `releases/` on `main`.
- **Download & Install**:
  1. Requests `Permission.requestInstallPackages`.
     - Denied → snackbar asking the user to allow "Install unknown apps"
       (with a **Settings** action when permanently denied).
     - No storage permission is requested.
  2. Downloads the APK to the app external directory (Dio, with progress).
  3. Opens the APK with `open_filex` so Android's installer takes over.
- There is **no** "Open in browser instead" option anymore.

---

## 6. Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| Only a toast shows, no permission dialog | The code is requesting `Permission.storage` (auto-denied on modern Android). Request `Permission.requestInstallPackages` instead. |
| APK won't install ("unknown apps" blocked) | `REQUEST_INSTALL_PACKAGES` missing in the manifest, or the user hasn't enabled "Install unknown apps" for Rent Manager. |
| App shows the old version after installing | `pubspec.yaml` `version:` was not bumped (or not rebuilt). Bump it and rebuild. |
| `Failed to find target with hash string 'android-37'` | SDK platform folder mismatch — see section 4. |
| Updater says "up to date" but a new APK exists | APK name version is not greater than the installed `versionName`. |
