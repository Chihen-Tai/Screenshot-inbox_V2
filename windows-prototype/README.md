# Screenshot Inbox Windows Prototype

This is a read-only Windows-ready proof of concept for opening an existing Screenshot Inbox managed library outside the macOS app.

It is not a production Windows app and does not aim for feature parity. Its only job is to validate that the library folder and SQLite schema can be consumed by another platform.

## Technology

- .NET 10
- C#
- Avalonia 12 UI
- `Microsoft.Data.Sqlite`

Avalonia was chosen instead of WinUI 3 because it can be built from a normal .NET SDK on macOS, Windows, or Linux while still giving the future Windows app a native-feeling desktop UI path. WinUI 3 remains a possible production choice later, but it would require Visual Studio and Windows App SDK on Windows for normal development.

## Structure

```text
windows-prototype/
  ScreenshotInbox.Windows.sln
  ScreenshotInbox.CoreBridge/
    Models/
    Services/
  ScreenshotInbox.Windows/
    App.axaml
    MainWindow.axaml
    ViewModels/
    Models/
  ScreenshotInbox.Tests/
```

`ScreenshotInbox.CoreBridge` contains the reusable read-only library reader. `ScreenshotInbox.Windows` contains the prototype UI. `ScreenshotInbox.Tests` contains path-portability tests.

## Prerequisites

Install the .NET 10 SDK:

```powershell
dotnet --version
```

Expected: `10.x` or newer.

The first restore/build downloads NuGet packages for Avalonia, `Microsoft.Data.Sqlite`, and xUnit.

## Build

From the repository root:

```powershell
cd windows-prototype
dotnet restore ScreenshotInbox.Windows.sln
dotnet build ScreenshotInbox.Windows.sln -c Debug
```

## Run

```powershell
cd windows-prototype
dotnet run --project ScreenshotInbox.Windows/ScreenshotInbox.Windows.csproj
```

Then:

1. Click **Open Library**.
2. Select the `Screenshot Inbox Library` folder.
3. The app opens `<library-root>/screenshot-inbox.sqlite` in read-only mode.
4. Screenshot records appear in the list.
5. Search filters by filename and OCR text when OCR rows exist.
6. Selecting a row shows metadata and resolved paths.

## What It Reads

Minimum required table:

- `screenshots`

Optional table joined when present in the current schema:

- `ocr_results`

The first prototype reads:

- UUID
- filename
- `library_path`
- `original_path`
- hash
- dimensions
- file size
- format
- source app
- created/imported/modified timestamps
- favorite/trash state
- OCR text for simple search

## Thumbnail and Image Loading

The UI tries thumbnail paths first:

```text
Thumbnails/small/<uuid>.jpg
Thumbnails/large/<uuid>.jpg
```

If no thumbnail exists, it tries the managed image path resolved from `library_path`. If neither exists, the row shows a placeholder block and does not crash.

The prototype does not generate thumbnails and does not write cache files.

## Read-only Safety

The SQLite connection uses read-only mode. The prototype does not:

- run migrations
- write to SQLite
- delete files
- rename files
- move items to trash
- rewrite paths
- generate thumbnails on disk

Any write behavior belongs in a future phase.

## Current Limitations

- No editing, import, OCR, QR detection, export, source sync, trash actions, duplicate cleanup, or rules.
- No full smart search parser.
- No schema migration runner.
- `original_path` may point to a macOS-only external source and is shown as provenance only.
- If old libraries contain absolute macOS `library_path` values, the prototype reports a portability warning and image loading may fail.
- This workspace did not have `dotnet` installed, so local build verification was not possible here.
