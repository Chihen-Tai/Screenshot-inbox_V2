# Screenshot Inbox Alpha Testing Guide

Thank you for testing Screenshot Inbox.

This guide is for external alpha testers. Please test with non-sensitive screenshots whenever possible.

## Quick Start

```bash
git clone https://github.com/Chihen-Tai/Screenshot-inbox_V2.git
cd Screenshot-inbox_V2
swift build
swift run ScreenshotInbox
```

The project is a Swift Package Manager executable. It is not an Xcode project, although you can open `Package.swift` in Xcode.

## Before You Test

- Quit any previously installed `Screenshot Inbox.app` copies if you are testing with `swift run`.
- Use screenshots that are safe to share if you plan to attach bug-report images.
- Do not post private screenshots, API keys, personal paths, or sensitive OCR text in public issues.

## Basic Launch Test

- [ ] Run `swift run ScreenshotInbox`.
- [ ] Confirm the app launches.
- [ ] Confirm the Dock icon opens or focuses the Main Inbox.
- [ ] Confirm the menu bar item appears if enabled.
- [ ] Confirm Main Inbox, Floating Preview, and Settings do not duplicate when opened repeatedly.

## Screenshot Capture Test

- [ ] Take one macOS screenshot.
- [ ] Confirm it appears exactly once in the Main Inbox.
- [ ] Confirm Floating Preview appears if auto-show is enabled.
- [ ] Confirm the menu-bar count increases by one.
- [ ] Take three screenshots quickly.
- [ ] Confirm exactly three new items appear.
- [ ] Confirm there are no duplicate filename/time entries.

## Floating Preview Test

- [ ] Open Floating Preview from the menu bar.
- [ ] If no screenshots are new, confirm the empty state is readable.
- [ ] Take a screenshot while Floating Preview is already open.
- [ ] Confirm the screenshot appears inside the same panel.
- [ ] Confirm no second Floating Preview window appears.
- [ ] Click the expand icon and confirm Main Inbox opens.
- [ ] Click the close icon and confirm only the panel hides.
- [ ] Confirm closing Floating Preview does not dismiss or delete screenshots.
- [ ] Right-click a screenshot row and try the context menu.
- [ ] Double-click a row or thumbnail and confirm Quick Look opens if implemented.
- [ ] Drag a screenshot from Floating Preview to Finder or Desktop.

## Menu Bar Count and Dismiss Test

- [ ] Take five screenshots.
- [ ] Confirm the menu-bar badge/count shows five new screenshots.
- [ ] Dismiss one screenshot from Floating Preview.
- [ ] Confirm the count becomes four.
- [ ] Dismiss the remaining screenshots.
- [ ] Confirm the count becomes zero or the badge disappears.
- [ ] Confirm dismissed screenshots are not deleted.
- [ ] Confirm closing Floating Preview without dismissing does not change the count.

## Main Inbox Test

- [ ] Open Main Inbox.
- [ ] Confirm the rich Inbox UI appears, not a simplified All/New/Dismissed-only window.
- [ ] Confirm the grid shows screenshot thumbnails.
- [ ] Select one screenshot and confirm the preview/action panel updates.
- [ ] Search by filename.
- [ ] Search by OCR text if OCR has completed.
- [ ] Try right-click actions.
- [ ] Try Copy.
- [ ] Try Reveal in Finder.
- [ ] Try Quick Look with Space.
- [ ] Try drag-out to Finder or Desktop.
- [ ] Try Cmd+A and Escape if selection shortcuts are implemented.

## Settings Test

Open Settings from the menu bar or app menu.

- [ ] Confirm Settings opens as one separate window.
- [ ] Confirm repeated Settings clicks reuse the same window.
- [ ] Confirm Screenshot Capture settings exist.
- [ ] Confirm Floating Preview settings exist.
- [ ] Confirm Menu Bar settings exist.
- [ ] Toggle Floating Preview auto-show off.
- [ ] Take a screenshot.
- [ ] Confirm the screenshot is collected but Floating Preview does not auto-pop.
- [ ] Manually open Floating Preview and confirm the screenshot is there.
- [ ] Re-enable auto-show and confirm future screenshots show the panel after the configured delay.

## Export / PDF Test

- [ ] Select one screenshot.
- [ ] Export as PDF.
- [ ] Open the PDF and confirm it has one page.
- [ ] Select multiple screenshots.
- [ ] Combine into PDF.
- [ ] Open the PDF and confirm page count and order.
- [ ] Export originals and confirm copied files exist.
- [ ] Cancel a save panel and confirm no error appears.

## OCR / QR Test

- [ ] Capture or import a screenshot with English text.
- [ ] Confirm OCR completes.
- [ ] Search for a word from the screenshot.
- [ ] Capture or import a screenshot with Chinese text if available.
- [ ] Search for Chinese text.
- [ ] Capture or import a screenshot with a QR code.
- [ ] Confirm the QR payload or link appears if supported.
- [ ] Confirm no network upload occurs for local OCR/QR processing.

## Relaunch Test

- [ ] Quit the app.
- [ ] Relaunch with `swift run ScreenshotInbox`.
- [ ] Confirm Main Inbox opens.
- [ ] Confirm the library still loads.
- [ ] Confirm Settings still opens.
- [ ] Confirm menu-bar count is not incorrectly reset.

## Bug Report Checklist

When filing a bug, include:

- macOS version
- Mac model and Apple Silicon / Intel
- How you ran the app: `swift run`, downloaded app, or other
- App commit hash if known
- Steps to reproduce
- Expected behavior
- Actual behavior
- Screenshots or screen recordings, if safe
- Console logs, if useful

Please use `.github/ISSUE_TEMPLATE/bug_report.md`.
