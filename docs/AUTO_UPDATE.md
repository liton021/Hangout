# 🔄 In-App Auto-Update (GitHub Releases — no Cloudflare needed)

When the user opens Hangout, the app quietly asks GitHub whether a newer
release exists. If yes, it shows **"Update available 🎉"** with the release
notes. The user taps **Update now** → the APK downloads with a progress bar →
the system installer opens. No Cloudflare, no FCM, no Play Store.

```
GitHub Releases API (releases/latest)
        │  (free, public, no auth)
        ▼
App on launch ──► newer? ──► dialog ──► download APK ──► system installer
```

---

## Part 1 — Create the release workflow (ONE-TIME, ~2 min)

This session's bot cannot push workflow files (GitHub restricts that), so
create it once in the web editor:

1. GitHub repo → **Actions** tab → **New workflow** → **set up a workflow yourself**.
2. Name the file: `release.yml`
3. Delete the starter content and paste exactly this:

```yaml
name: Build and Release APK

# Runs when you push a version tag like v1.0.1. Builds a universal APK
# and attaches it to a GitHub Release — the app's updater finds it there.
on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
          channel: 'stable'

      - name: Install dependencies
        working-directory: hangout_app
        run: flutter pub get

      - name: Build release APK (universal)
        working-directory: hangout_app
        run: flutter build apk --release

      - name: Rename APK with the version tag
        working-directory: hangout_app
        run: |
          mv build/app/outputs/flutter-apk/app-release.apk \
             build/app/outputs/flutter-apk/Hangout-${{ github.ref_name }}.apk

      - name: Upload APK to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: hangout_app/build/app/outputs/flutter-apk/Hangout-${{ github.ref_name }}.apk
          generate_release_notes: true
```

4. Click **Commit changes**.

> The trigger `v*.*.*` only matches tags like `v1.0.1` — the older
> auto-generated tags (`v-e9b0264…`) will **not** trigger it.

---

## Part 2 — How the app side works (already in the code)

| Piece | File |
|---|---|
| Version check + download + install logic | `hangout_app/lib/services/update_service.dart` |
| Installed version + repo constant | `hangout_app/lib/config/app_config.dart` (`appVersion`, `githubRepo`) |
| Prompt on launch (once per session) | `hangout_app/lib/app.dart` |
| Manual "Check for updates" row | Settings screen |
| Native installer (FileProvider + ACTION_VIEW) | `MainActivity.kt` |
| Install permission + provider | `AndroidManifest.xml`, `res/xml/file_paths.xml` |

Notes:

- **No Cloudflare needed** — the GitHub Releases API is public and free
  (60 requests/hour per IP, plenty for occasional checks).
- The check runs **after sign-in**, never blocks the UI, and fails silently
  (offline / no releases → nothing happens).
- Downloads go to the app's own external files dir; a re-download is
  skipped when the file already matches the release size.
- Android asks the user once to **"Allow installs from this app"** (system
  screen) — after that, updates install with one tap.

---

## Part 3 — Ship an update (2 minutes, every time)

1. **Bump the version** in `hangout_app/lib/config/app_config.dart`:
   ```dart
   static const String appVersion = '1.0.1';   // was '1.0.0'
   ```
   (Also update `version:` in `pubspec.yaml` to match, e.g. `1.0.1+2`.)
2. **Commit & push** (to `main`).
3. **Create the tag** — GitHub repo → **Releases** → **Draft a new release** →
   **Choose a tag** → type `v1.0.1` (exactly `v` + the new `appVersion`) →
   write release notes in the description → **Publish release**.
4. The `release.yml` workflow builds the universal APK and attaches it to
   the release automatically.
5. Users who open the app see **"Update available 🎉 v1.0.1"** with your
   release notes → Update now → installed.

> The release notes text you write in GitHub becomes what users see in the
> update dialog.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No prompt appears after publishing | The release tag must be **newer** than `AppConfig.appVersion` (compare `v1.0.1` vs `1.0.0`). Also make sure the release has an **APK asset** (workflow ran green). |
| "Download failed" in the dialog | No internet, or GitHub API rate limit (rare). Retry later. |
| Installer never opens | Android's "install unknown apps" permission — the app opens the system screen once; allow it and tap the APK again. |
| Release has no APK asset | The `release.yml` workflow failed — check the Actions tab log. |
| `v-e9b0264…` tags make noise | They don't match `v*.*.*`, so they're ignored. |

## Why not Cloudflare for this?

Cloudflare would only add a hop — GitHub already serves the APK bytes (via
its release CDN) and the version metadata. Using the GitHub API directly is
simpler, free, and has no extra moving parts to break.
