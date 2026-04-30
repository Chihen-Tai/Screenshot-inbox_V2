# Release Guide

This project is prepared for GitHub distribution outside the Mac App Store. It is currently a Swift Package Manager executable, so release packaging is handled by scripts that create a simple `.app` bundle under `dist/`.

## Current Version

- Version: `0.1.0-alpha`
- Build: `1`
- Bundle identifier placeholder: `com.chihentai.screenshotinbox`
- License: MIT

Version values are defined in:

- `ScreenshotInbox/App/AppReleaseInfo.swift`
- `scripts/build-release.sh`
- `scripts/package-zip.sh`
- `scripts/package-dmg.sh`
- `CHANGELOG.md`

Before a release, keep these values in sync.

## Build Paths

Debug build:

```bash
swift build
swift run ScreenshotInbox
```

Release executable build:

```bash
swift build -c release
```

Release app bundle:

```bash
scripts/build-release.sh
```

Output:

```text
dist/Screenshot Inbox.app
```

The bundle script:

- Builds with `swift build -c release`
- Creates `dist/Screenshot Inbox.app`
- Copies the SwiftPM executable
- Copies the SwiftPM resource bundle
- Generates `Contents/Info.plist`
- Generates `Contents/Resources/AppIcon.icns` when `iconutil` is available
- Ad-hoc signs by default

## App Icon

The app icon source is:

```text
ScreenshotInbox/Resources/Assets.xcassets/AppIcon.appiconset/
```

The set includes standard macOS icon sizes from 16x16 through 1024x1024. The release script converts that icon set into `AppIcon.icns` for the app bundle.

Verify before release:

- Finder shows the custom icon for `Screenshot Inbox.app`
- Dock shows the custom icon after launch
- About panel shows the custom icon

## About Panel

The app uses the native macOS About panel from `AppCommands`.

Expected About content:

- App name: Screenshot Inbox
- Version: 0.1.0-alpha
- Build: 1
- Copyright: Copyright © 2026 Chihen Tai
- License: MIT
- Description: A local-first macOS screenshot organizer.
- Privacy note: Local-first. No account required.
- GitHub repository placeholder

## First-Run Onboarding

The first-run onboarding sheet explains:

- The app creates a local managed library
- Screenshots stay on this Mac
- OCR and QR detection run locally
- Auto import can watch folders such as Desktop or Downloads when enabled
- Original source files are not modified by default

The dismissal state is stored in UserDefaults key:

```text
ScreenshotInbox.hasSeenOnboarding
```

For manual testing, reset it with:

```bash
defaults delete com.chihentai.screenshotinbox ScreenshotInbox.hasSeenOnboarding
```

The bundle identifier may differ in unsigned local SwiftPM runs.

## Packaging

ZIP package:

```bash
scripts/package-zip.sh
```

Output:

```text
dist/ScreenshotInbox-0.1.0-alpha.zip
```

DMG package:

```bash
scripts/package-dmg.sh
```

Output:

```text
dist/ScreenshotInbox-0.1.0-alpha.dmg
```

The DMG script creates a simple disk image with the app bundle and an Applications shortcut. It does not use custom artwork.

## Code Signing

For local testing, the release script ad-hoc signs by default:

```bash
scripts/build-release.sh
```

To skip signing:

```bash
SKIP_CODESIGN=1 scripts/build-release.sh
```

For public distribution, use a Developer ID Application certificate:

```bash
SIGN_IDENTITY="Developer ID Application: <Your Developer ID>" scripts/build-release.sh
```

Do not commit signing identities, certificates, profiles, passwords, or API keys.

## Notarization

Notarization is recommended for smoother opening on macOS outside the App Store.

Use the example script as a starting point:

```bash
cp scripts/notarize.sh.example scripts/notarize.sh
```

Then provide credentials through environment variables, not committed files:

```bash
APPLE_ID="you@example.com" \
TEAM_ID="TEAMID1234" \
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
BUNDLE_ID="com.chihentai.screenshotinbox" \
scripts/notarize.sh dist/ScreenshotInbox-0.1.0-alpha.dmg
```

Create an app-specific password from Apple ID account settings. Use `xcrun notarytool submit --wait` to submit. Staple notarization tickets to DMG files with `xcrun stapler staple`, then verify with `spctl`.

## Permission and Privacy Notes

Screenshot Inbox is local-first. It does not upload screenshots or OCR text to any server.

It uses chosen folders, a managed library under Pictures, file open panels, file-system watchers, and Apple local OCR/QR APIs.

Current release notes for users:

- Screenshots are copied into a local managed library.
- Original Desktop, Downloads, or source files are not modified by default.
- Watched folders are configurable in Settings.
- Only configured watched folders are monitored.
- No telemetry or network services are included.
- The app is not currently distributed through the Mac App Store sandbox.
- Future sandboxing work should use security-scoped bookmarks for user-selected folders.
- Folder access preparation is represented in `FolderAccessService`; sandboxing remains deferred for GitHub builds.

## Manual Release Tests

1. Clean build Release.
   Expected: app builds.
2. Launch Release build.
   Expected: no debug controls visible.
3. Open About window.
   Expected: name, version, license, copyright, description, and privacy note are correct.
4. First launch onboarding.
   Expected: appears once, can be dismissed, and does not appear again unless reset.
5. Package ZIP.
   Expected: ZIP contains `Screenshot Inbox.app`.
6. Move app to Applications.
   Expected: app launches.
7. Import image.
   Expected: image imports into the managed library.
8. Export PDF.
   Expected: selected screenshots export.
9. Settings.
   Expected: settings window opens correctly.
10. Signing/notarization scripts.
    Expected: scripts use placeholders only and no credentials are committed.

## GitHub Release Checklist

Before release:

- Update version.
- Update `CHANGELOG.md`.
- Build Release.
- Test fresh launch.
- Test import.
- Test OCR/search.
- Test PDF export.
- Test Settings.
- Test Trash/Restore.
- Verify no debug UI.
- Confirm no hardcoded local paths.
- Confirm no API keys, tokens, signing identities, certificates, profiles, or passwords are committed.
- Confirm release build hides debug logs that include full file paths, OCR text, QR payloads, or folder paths.
- Confirm `PRIVACY.md` is accurate for the release.
- Confirm auto import folders are user-visible and controllable in Settings.
- Confirm original source files are not modified by default.
- Confirm no screenshots, OCR text, or detected code payloads are uploaded.
- Verify app icon in Finder, Dock, and About panel.
- Package ZIP and optionally DMG.
- Sign if Developer ID is available.
- Notarize if Developer ID is available.
- Upload release asset to GitHub.
- Add public screenshots to `docs/images/` when available.
