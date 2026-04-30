# Release Guide

This project is prepared for GitHub distribution outside the Mac App Store. It is currently a Swift Package Manager executable, so release packaging is handled by scripts that create a simple `.app` bundle under `dist/`.

## Current Version

- Development version: `0.4.0-alpha-dev`
- Final alpha version: `0.4.0-alpha`
- Build: `4`
- Bundle identifier placeholder: `com.chihentai.screenshotinbox`
- License: MIT

Development builds use the `-dev` suffix, are for local testing, and may not be notarized. Do not produce final `0.4.0-alpha` artifacts until the current bugfix checklist and manual tests pass.

Final alpha release builds use `0.4.0-alpha` with build `4` and are produced only after the bugfix checklist passes.

Version values are defined in:

- `ScreenshotInbox/App/AppReleaseInfo.swift`
- `scripts/build-release.sh`
- `scripts/package-zip.sh`
- `scripts/package-dmg.sh`
- `scripts/verify-release.sh`
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
- Version: 0.4.0-alpha-dev during testing; 0.4.0-alpha for final alpha
- Build: 4
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
dist/ScreenshotInbox-0.4.0-alpha-dev.zip
```

DMG package:

```bash
scripts/package-dmg.sh
```

Output:

```text
dist/ScreenshotInbox-0.4.0-alpha-dev.dmg
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

For public distribution, use a Developer ID Application certificate. Set the environment variable, then build; the script switches on hardened runtime and a secure timestamp automatically:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: <Your Name> (TEAMID1234)" \
  scripts/build-release.sh
```

The script signs the bundle only after every resource has been copied. The bundle is not modified afterward. Verification runs immediately after signing:

```bash
codesign -dv --verbose=4 "dist/Screenshot Inbox.app"
codesign --verify --deep --strict --verbose=2 "dist/Screenshot Inbox.app"
spctl --assess --type execute --verbose=4 "dist/Screenshot Inbox.app"
```

Ad-hoc signed builds will fail `spctl` with `source=Unnotarized`. That is expected for local testing only. Public builds require Developer ID signing and notarization.

You can also run the bundled verification helper:

```bash
scripts/verify-release.sh "dist/Screenshot Inbox.app"
```

Do not commit signing identities, certificates, profiles, passwords, or API keys.

## Why macOS Says the App Cannot Be Verified

Downloaded builds may trigger:

```text
Apple cannot verify "Screenshot Inbox" is free of malware.
```

macOS adds the `com.apple.quarantine` extended attribute to downloaded apps. Gatekeeper then checks Developer ID signing and Apple notarization. Ad-hoc signing is useful for local testing only; it does not make a public GitHub download pass Gatekeeper.

The reliable public release fix is:

- Sign with a Developer ID Application certificate.
- Submit the app or DMG to Apple notarization.
- Staple the notarization ticket where supported.

If Developer ID credentials are unavailable, do not claim the Gatekeeper warning is fully fixed.

## Local Quarantine Testing

For local developer testing only, a helper is provided:

```bash
scripts/remove-quarantine-local.sh "dist/Screenshot Inbox.app"
```

Equivalent command:

```bash
xattr -dr com.apple.quarantine "/path/to/Screenshot Inbox.app"
```

This is only for local developer testing. Public releases should be Developer ID signed and notarized.

## Notarization

Notarization is required for smooth opening of public GitHub downloads. Without it, Gatekeeper will reject the app on every other user's Mac.

Public release path:

1. Build with `DEVELOPER_ID_APPLICATION` set so the script signs with hardened runtime and a secure timestamp.
2. Verify codesign is clean.
3. Package the signed bundle with `scripts/package-zip.sh` and/or `scripts/package-dmg.sh`.
4. Submit the resulting artifact to Apple notary using `notarytool`.
5. Staple the result (DMG or `.app`; ZIP cannot be stapled directly).
6. Verify with `spctl`.
7. Upload the signed, notarized, stapled artifact to GitHub Releases.

Use the example script as a starting point:

```bash
cp scripts/notarize.sh.example scripts/notarize.sh
```

Then provide credentials through environment variables, not committed files:

```bash
APPLE_ID="your-apple-id@example.com" \
TEAM_ID="YOURTEAMID" \
APP_SPECIFIC_PASSWORD="@keychain:AC_PASSWORD" \
BUNDLE_ID="com.chihentai.screenshotinbox" \
scripts/notarize.sh dist/ScreenshotInbox-0.4.0-alpha.dmg
```

Reference command shape (placeholders only — never commit credentials):

```bash
xcrun notarytool submit "dist/ScreenshotInbox-0.4.0-alpha.dmg" \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOURTEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

xcrun stapler staple "dist/ScreenshotInbox-0.4.0-alpha.dmg"
xcrun stapler validate "dist/ScreenshotInbox-0.4.0-alpha.dmg"
spctl -a -vv --type open --context context:primary-signature \
  "dist/ScreenshotInbox-0.4.0-alpha.dmg"
```

Create an app-specific password from Apple ID account settings, or store it in the macOS keychain and reference it with the `@keychain:` prefix.

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

## 0.4.0-alpha-dev Local Test Checklist

- [ ] Update version (`AppReleaseInfo.swift`, `build-release.sh`, `package-zip.sh`, `package-dmg.sh`).
- [ ] Update `CHANGELOG.md`.
- [ ] Clean build (`scripts/build-release.sh`).
- [ ] Sign app (ad-hoc by default; Developer ID via `DEVELOPER_ID_APPLICATION`).
- [ ] Verify `codesign --verify --deep --strict --verbose=2`.
- [ ] Run `spctl --assess --type execute --verbose=4` and record the result.
- [ ] Package ZIP with `scripts/package-zip.sh`.
- [ ] Verify ZIP contents pass codesign verification after extraction.
- [ ] Launch the bundled app locally.
- [ ] Test import.
- [ ] Test Settings.
- [ ] Test PDF export.
- [ ] Test OCR/QR basic behavior.
- [ ] Confirm no DEBUG-only UI is reachable in Release.
- [ ] Confirm no local user paths are bundled into resources.

## Final 0.4.0-alpha Release Gate

Only after the bugfix manual checklist passes:

- Change `CFBundleShortVersionString` / `AppReleaseInfo.version` from `0.4.0-alpha-dev` to `0.4.0-alpha`.
- Keep `CFBundleVersion` / `AppReleaseInfo.build` at `4`.
- Package `dist/ScreenshotInbox-0.4.0-alpha.zip`.
- Package `dist/ScreenshotInbox-0.4.0-alpha.dmg` only if DMG packaging is used.
- Update `CHANGELOG.md`.
- Create or prepare the GitHub release draft after the final package exists.

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
