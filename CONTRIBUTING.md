# Contributing

Thank you for considering a contribution to Screenshot Inbox.

## Reporting Bugs

When reporting a bug, include:

- macOS version
- Xcode or Swift version, if building from source
- Steps to reproduce
- Expected result
- Actual result
- Relevant logs or screenshots, with private information removed

Do not attach personal screenshots unless they are safe to share publicly.

## Suggesting Features

Feature requests are welcome. Please describe:

- The workflow you want to improve
- Why the current app behavior is not enough
- Any privacy, local-file, or macOS permission considerations

## Building Locally

```bash
swift build
swift test
swift run ScreenshotInbox
```

The project is a Swift Package Manager executable. You can also open `Package.swift` in Xcode.

## Coding Style

- Prefer existing app patterns over new abstractions.
- Keep UI state routed through `AppState` where appropriate.
- Keep platform-specific code under `Platform/macOS/`.
- Keep repository and SQLite code under `Persistence/`.
- Avoid new dependencies unless they are clearly needed and discussed.
- Add focused tests for behavior changes.

## Repository Hygiene

Please avoid committing:

- Local build artifacts
- DerivedData
- SQLite databases
- Personal screenshots
- Generated thumbnails
- Exported PDFs unless intentionally added as documentation assets
- API keys, tokens, passwords, or private paths

Use `docs/images/` for public README screenshots and demo images.
