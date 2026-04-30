# Privacy

Screenshot Inbox is designed as a local-first macOS app.

## Local-First Design

Screenshot Inbox is local-first. It does not upload your screenshots or OCR text to any server.

The app does not require an account, cloud sync, telemetry service, or external API to organize screenshots. Core workflows run on your Mac:

- Screenshots stay on your Mac.
- OCR runs locally using Apple frameworks.
- QR and code detection runs locally using Apple frameworks.
- Search runs against local filenames, metadata, tags, OCR text, and detected codes.
- The SQLite database is stored locally.
- Managed library files are stored locally.

## Stored Files

Imported screenshots are copied into a managed library on your Mac. By default, the library is located at:

```text
~/Pictures/Screenshot Inbox Library/
```

The managed library may contain:

- Original imported screenshots under `Originals/`
- Generated thumbnails under `Thumbnails/`
- A SQLite database with metadata at `screenshot-inbox.sqlite`
- OCR text stored in SQLite
- Detected QR codes, links, or payloads stored in SQLite
- Tags, collections, favorites, trash state, and organization rules
- Exported PDFs if you choose to save them there

## OCR and QR Processing

OCR and QR detection run locally using Apple frameworks. Screenshot Inbox does not need to upload images to a cloud service for these features.

## Watched Folders

Only configured watched folders are monitored.

Watched folders are visible in Settings. Users can enable, disable, add, remove, and manually scan watched folders there. Development defaults may include common screenshot locations such as Desktop and Downloads.

Screenshot Inbox does not scan arbitrary folders. Existing files in watched folders are imported only when the user explicitly chooses a scan/import action. Auto Import watches configured folders for new image files.

## Source Files

Original source files are not modified by default.

Import copies files into the managed library. The original path is kept as a reference to where the file came from. Normal rename, trash, restore, and delete workflows operate on Screenshot Inbox records and managed library copies, not the original Desktop, Downloads, or other source files.

Original source rename/delete behavior is intentionally disabled unless a future explicit setting and permission model is added.

## Trash and Deletion

App Trash affects screenshots in the managed library. Permanent deletion removes managed-library records and managed files, not unrelated source files outside the managed library.

## Folder Access and Sandbox Status

GitHub builds are currently non-sandboxed so local import, file watching, export, and Finder reveal workflows keep working outside the Mac App Store.

The codebase includes a `FolderAccessService` abstraction as preparation for a future sandboxed release. Future sandboxed builds should store security-scoped bookmarks for user-selected watched folders and export destinations, validate access on launch, and prompt users to re-authorize folders when access fails.

When folder access fails, the app should explain the problem in user-facing text, for example: "Screenshot Inbox cannot access this folder. Please choose it again in Settings."

## Telemetry

No telemetry or network services are included.

The app does not include telemetry, analytics, advertising, crash-reporting SDKs, tracking, account services, cloud upload, or external API calls in the current open-source codebase. If telemetry is ever added, it should be documented, optional, disabled by default unless explicitly accepted, and reviewed before release.

## Data Sale or Transmission

The app does not sell or transmit user data. No cloud upload is required for normal use.

## Removing Local Data

To remove Screenshot Inbox data from your Mac:

1. Empty the app Trash if you want managed copies removed from inside the app.
2. Remove watched folders in Settings if you no longer want them monitored.
3. Quit the app.
4. Delete the managed library folder:

```text
~/Pictures/Screenshot Inbox Library/
```

Deleting the managed library removes Screenshot Inbox copies, thumbnails, the SQLite database, OCR text, detected code data, tags, collections, and app trash records. It does not delete original source files outside the managed library.
