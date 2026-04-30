# Privacy

Screenshot Inbox is designed as a local-first macOS app.

## Local-First Design

The app does not require an account, cloud sync, or an external service to organize screenshots. Core workflows run on your Mac.

## Stored Files

Imported screenshots are copied into a managed library on your Mac. By default, the library is located at:

```text
~/Pictures/Screenshot Inbox Library/
```

The managed library may contain:

- Original imported screenshots
- Generated thumbnails
- A SQLite database with metadata
- OCR results
- Detected QR codes or links
- Tags, collections, favorites, trash state, and organization rules
- Exported PDFs if you choose to save them there

## OCR and QR Processing

OCR and QR detection run locally using Apple frameworks. Screenshot Inbox does not need to upload images to a cloud service for these features.

## Watched Folders

Watched folders are user-controlled. Development defaults may include common screenshot locations such as Desktop and Downloads, but users can manage import sources in Settings.

## Source Files

Original Desktop, Downloads, or other source files are not deleted by default. Screenshot Inbox works with managed copies inside its library unless a future permissioned feature explicitly changes that behavior.

## Trash and Deletion

App Trash affects screenshots in the managed library. Permanent deletion removes managed-library records and managed files, not unrelated source files outside the managed library.

## Telemetry

The app does not include telemetry, analytics, advertising, or tracking in the current open-source codebase. If telemetry is ever added, it should be documented, optional, and reviewed before release.

## Data Sale or Transmission

The app does not sell user data. No cloud upload is required for normal use.
