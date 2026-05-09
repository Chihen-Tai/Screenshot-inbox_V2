# Screenshot Inbox

A screenshot inbox that keeps your screenshots until you are ready.

Screenshot Inbox is a native macOS app for collecting, organizing, searching, and exporting screenshots. It is local-first, uses a managed library on your Mac, and supports a Floating Preview tray, OCR, QR code detection, tags, collections, PDF export, and cleanup tools.

> **Alpha status:** Screenshot Inbox is in active pre-release development. It is ready for hands-on testing, but testers should expect bugs and rough edges.

## Why it exists

macOS shows a screenshot preview for only a few seconds. Screenshot Inbox keeps screenshots available in a persistent inbox so you can review, rename, tag, export, or delete them later.

## Quick Start for Testers

The safest way to test the alpha is to run from source. Unsigned app bundles or DMGs may trigger macOS security warnings.

```bash
git clone https://github.com/Chihen-Tai/Screenshot-inbox_V2.git
cd Screenshot-inbox_V2
swift build
swift run ScreenshotInbox
```

The project is a Swift Package Manager executable target, not an Xcode project. If you prefer Xcode, open `Package.swift`.

## Requirements

- macOS 14 or later, based on the package platform declaration.
- Swift 5.10 or later, based on `Package.swift`.
- Xcode 15.3 or later is recommended for Swift 5.10 and macOS SDK support.
- OCR and QR detection use Apple frameworks and require macOS support for the relevant Vision APIs.

## What to Test

See [`TESTING_GUIDE.md`](TESTING_GUIDE.md) for the full alpha tester checklist.

A short smoke test:

1. Launch with `swift run ScreenshotInbox`.
2. Take one macOS screenshot.
3. Confirm the Floating Preview appears if auto-show is enabled.
4. Confirm the screenshot appears exactly once in the Main Inbox.
5. Take several screenshots quickly and check that the count is correct.
6. Open Settings and verify Screenshot Capture, Floating Preview, and Menu Bar options.
7. Try Copy, Reveal in Finder, Quick Look, drag-out, and PDF export.
8. Quit and relaunch.

## Features

- Native macOS interface
- Local screenshot library
- Manual image import
- Auto import from watched folders
- Floating Preview Panel with menu-bar badge for real-time new-screenshot notifications
- Sidebar collections
- Tags
- Favorites
- App trash and restore
- OCR text extraction
- QR code and link detection
- Search across filenames, OCR text, tags, collections, and detected codes
- Export selected screenshots as PDF (Cmd+Shift+E)
- Export original images (Cmd+E)
- Reveal in Finder after export
- Duplicate and cleanup tools
- Library maintenance and repair tools

## Screenshots

### Main window

![Main window](docs/images/main.png)

### OCR and search

![OCR and QR](docs/images/qrocr.png)
![Search](docs/images/search.png)

### PDF export

![PDF export](docs/images/pdf.png)

### Settings

![Settings](docs/images/setting.png)

## Usage

1. Import screenshots manually, or enable watched folders for auto import.
2. The Floating Preview Panel appears automatically when new screenshots arrive if auto-show is enabled. The menu-bar badge shows the unreviewed count.
3. Organize screenshots with collections, tags, and favorites.
4. Use OCR and search to find screenshots by text, filenames, tags, collections, or detected codes.
5. Use QR detection to open or copy links found in screenshots.
6. Select screenshots and press Cmd+Shift+E to combine into a PDF, or Cmd+E to export originals. Both open a save panel and reveal the exported file in Finder.
7. Use Trash and Restore for safe cleanup before permanent deletion.
8. Use library maintenance tools if thumbnails, OCR records, or library files need repair.

## Known Alpha Limitations

- The app is not yet distributed through the Mac App Store.
- Unsigned local builds may require source-based testing instead of a downloaded app bundle.
- Some workflows may still have layout, routing, or state-sync bugs.
- OCR, QR detection, PDF export, and duplicate cleanup should be treated as alpha features until more users test them.
- Do not attach private screenshots to public bug reports unless you are comfortable sharing them.

## Release Builds

The current pre-release version is `0.4.0-alpha` with build `4`.

Create a local release app bundle:

```bash
scripts/build-release.sh
```

Create a ZIP package:

```bash
scripts/package-zip.sh
```

Release packaging, signing, notarization, and manual QA steps are documented in `docs/RELEASE.md`.

## Project Structure

```text
ScreenshotInbox/
  App/                 SwiftUI app entry, app state, app commands, permissions, routing
  AppKitBridge/        NSCollectionView grid, menu bar, floating preview, AppKit controllers
  Core/                Shared service protocols
  Models/              App value types
  Persistence/         SQLite repositories and migrations
  Platform/macOS/      macOS-specific services
  Resources/           Assets and localized strings
  Services/            Import, OCR, QR detection, search, export, maintenance
  UI/                  SwiftUI views
  Utilities/           Shared helpers and design tokens
Tests/
  ScreenshotInboxTests/
```

See `ARCHITECTURE.md` and `docs/ARCHITECTURE.md` for more detail.

## Privacy

Screenshot Inbox is local-first. It does not upload your screenshots or OCR text to any server by default.

Screenshots are stored in a local managed library on your Mac. OCR and QR detection run locally using Apple frameworks. No account is required, no telemetry or network services are included, and watched folders are limited to the folders configured in Settings. Import, rename, trash, and delete workflows operate on managed Screenshot Inbox copies by default, not the original source files on your Desktop, Downloads, or other folders. Optional Source Folder Sync settings can rename or move original source files to macOS Trash only when explicitly enabled.

If future AI-provider features are enabled, review their settings and privacy notes before sending OCR text or metadata to an external provider.

See `PRIVACY.md` for details.

## Reporting Bugs

Please use the GitHub issue templates:

- **Bug report:** include macOS version, run method, commit hash, steps to reproduce, screenshots or screen recordings if safe, and console logs if available.
- **Feature request:** describe the workflow problem and the desired behavior.

Do not upload private screenshots or API keys in public issues.

## Current Status

Screenshot Inbox is in active pre-release development. Core local-library, import, organization, OCR, QR detection, search, PDF export, trash, and maintenance workflows exist, but the project still needs broader manual QA and public issue triage before a stable release.

## Roadmap

See `ROADMAP.md`.

## Contributing

Contributions are welcome. Please read `CONTRIBUTING.md` before opening issues or pull requests.

## License

MIT License. See `LICENSE`.

## Chinese Note

Screenshot Inbox 是一個本機優先的 macOS 截圖整理工具。主要說明文件以英文維護，歡迎補充繁體中文文件。
