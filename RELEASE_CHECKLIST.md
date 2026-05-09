# Screenshot Inbox Alpha Release Checklist

Version: `0.6.0-alpha` | Build: `5`

Use this checklist before tagging an alpha build. The goal is stabilization for real user testing, not new feature work.

## How To Build

```bash
swift build
swift test
scripts/check-architecture.sh
scripts/build-release.sh
scripts/verify-release.sh
```

Expected result: build and tests pass with no release-blocking warnings or errors.

## How To Run

Run the Swift Package Manager executable during development:

```bash
swift run ScreenshotInbox
```

For release-candidate QA, run the packaged app produced by `scripts/build-release.sh` and verify it behaves the same as the SPM executable.

## Manual QA Checklist

- [ ] App launches and opens the Main Inbox window
- [ ] Dock icon click reopens or focuses Main Inbox
- [ ] App menu and window metadata display `Screenshot Inbox`
- [ ] Menu bar command opens Main Inbox
- [ ] Menu bar command opens Floating Preview
- [ ] Menu bar command opens Settings
- [ ] Screenshot capture creates one inbox item
- [ ] Reprocessing the same screenshot is ignored as a duplicate
- [ ] Menu bar count updates after new captures and dismissals
- [ ] Floating Preview layout is usable with one and multiple items
- [ ] Floating Preview close hides the panel
- [ ] Floating Preview expand opens Main Inbox and selects the item when possible
- [ ] Main Inbox grid renders thumbnails in regular, medium, and compact widths
- [ ] Selection works: click, Cmd-click, Shift-click, Cmd-A, Escape
- [ ] Right-click menu opens for items and empty grid area
- [ ] Copy commands put image/file data on the pasteboard
- [ ] Reveal in Finder opens the selected managed file
- [ ] Quick Look opens from context menu and Space
- [ ] Settings opens and required sections load: Screenshot Capture, Floating Preview, Menu Bar
- [ ] Settings toggles affect behavior after closing/reopening the relevant surface
- [ ] PDF export completes if enabled
- [ ] OCR completes or fails without crashing if enabled
- [ ] QR/link detection completes or fails without crashing if enabled
- [ ] Quit and relaunch preserve the managed library and do not create duplicate app instances

## Logging Checklist

Keep console output quiet during normal use. Logs should remain for:

- [ ] Import failure
- [ ] Duplicate import ignored
- [ ] File missing
- [ ] OCR failure
- [ ] QR/code detection failure
- [ ] PDF export failure
- [ ] AI provider failure if AI is enabled
- [ ] Duplicate app instance prevention

Normal selection changes, hover, layout recalculation, successful copy/reveal, successful OCR/QR/PDF work, repeated auto-import scans, and menu/window refreshes should not spam the console.

## Alpha QA Notes

Last SPM alpha smoke pass: 2026-05-09.

- `swift build` passed after stabilization edits.
- `swift test` passed after stabilization edits: 79 tests across 23 suites.
- `scripts/check-architecture.sh` passed.
- `scripts/build-release.sh` passed with `VERSION=0.4.0-alpha BUILD_NUMBER=4`.
- `scripts/verify-release.sh` passed codesign verification; `spctl` rejected the ad-hoc, non-notarized build as expected.
- Main Inbox launched with real library rows.
- App menu displayed `Screenshot Inbox`.
- Debug executable metadata and packaged app metadata use `Screenshot Inbox`.
- Settings opened and included Screenshot Capture, Floating Preview, Menu Bar, OCR, AI Suggestions, and other existing sections.
- Floating Preview opened from the menu, displayed content, closed, and expanded to Main Inbox.
- A real screenshot imported from Desktop; touching the same file did not create a duplicate row.
- OCR and QR detection queues ran during import without crashing.
- Quit and relaunch worked in the SPM executable.

## Known Issues And Limitations

- SwiftPM debug runs may show the Dock tooltip/process name as `ScreenshotInbox`; app menu, debug metadata, and packaged app metadata display `Screenshot Inbox`.
- Packaged `.app` signing, notarization, and Gatekeeper behavior still need a full release-candidate pass before public distribution.
- Settings has many alpha-era sections, so the tab row can force a wider window than the nominal fixed size on smaller displays.
- `ScreenshotInboxStore` floating-preview inbox state is in-memory and does not persist across relaunches.
- No iCloud or network sync is implemented.
- Windows portability layer is not implemented.
- AI suggestions are optional and should fall back safely when no provider key is configured.

## Release Steps

1. Confirm the working tree contains only intentional alpha-stabilization changes.
2. Run `swift build`.
3. Run `swift test`.
4. Run `scripts/check-architecture.sh`.
5. Build the release app with `scripts/build-release.sh`.
6. Run `scripts/verify-release.sh`.
7. Launch the packaged app and repeat the manual QA checklist.
8. Update `CHANGELOG.md` and `docs/RELEASE.md` if user-facing behavior changed.
9. Create the release tag only after the packaged-app pass is clean or all remaining issues are documented as accepted alpha limitations.

## Before Tagging

- [ ] No P0 or P1 bugs remain open
- [ ] No screenshots are lost or deleted unexpectedly during QA
- [ ] Duplicate import prevention is verified with a real file
- [ ] Main Inbox, Floating Preview, Settings, and Menu Bar are all reachable
- [ ] Console logs are quiet in normal workflows
- [ ] Known limitations are documented
- [ ] Packaged app has been tested, not only `swift run`
