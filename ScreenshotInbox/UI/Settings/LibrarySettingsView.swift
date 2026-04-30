import SwiftUI

struct LibrarySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmRebuildAllThumbnails = false
    @State private var confirmCleanOrphanOriginals = false
    @State private var confirmVacuumDatabase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "Managed Library") {
                    Text(appState.library.libraryRootURL.path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    HStack {
                        Button("Reveal Library in Finder") {
                            appState.revealLibraryInFinder()
                        }
                        Button("Change Library Location") {}
                            .disabled(true)
                            .help("Changing library location is planned for a later phase.")
                    }
                    SettingsNote(text: "Screenshot Inbox currently runs in Library Mode. Imported files are copied into this managed folder.")
                }

                SettingsSection(title: "File Behavior / Source Folder Sync") {
                    SettingsNote(text: "By default, Screenshot Inbox works in Library Mode. Imported files are copied into a managed library. Renaming, trashing, or deleting items inside Screenshot Inbox affects the managed copy only. Original Desktop, Downloads, or source folder files are left unchanged unless Source Folder Sync is enabled.")

                    VStack(alignment: .leading, spacing: 8) {
                        SourceSyncStatusRow(
                            title: "Rename original source files when renaming screenshots",
                            status: "Coming later",
                            detail: "Currently OFF. Renames apply only to the managed library copy."
                        )
                        SourceSyncStatusRow(
                            title: "Move original source files to macOS Trash",
                            status: "Coming later",
                            detail: "Currently OFF. Trash only affects Screenshot Inbox managed files."
                        )
                        SourceSyncStatusRow(
                            title: "Delete original source files permanently",
                            status: "Not available",
                            detail: "Permanent source deletion is intentionally unavailable in this alpha."
                        )
                    }

                    SettingsNote(text: "Source Folder Sync remains off until original-file permissions, conflict handling, and explicit confirmations are implemented. Screenshot Inbox will not silently modify Desktop, Downloads, or watched-folder originals.")
                }

                SettingsSection(title: "Library Maintenance") {
                    if let status = appState.maintenanceStatusText {
                        Text(status)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let report = appState.libraryIntegrityReport {
                        LibraryHealthSummary(report: report)
                    } else {
                        SettingsNote(text: "Run an integrity check before repair actions. Repairs only operate inside the managed Screenshot Inbox library.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Run Integrity Check") {
                                appState.runLibraryIntegrityCheck()
                            }
                            Button("Regenerate Missing Thumbnails") {
                                appState.regenerateMissingThumbnails()
                            }
                            Button("Rebuild All Thumbnails") {
                                confirmRebuildAllThumbnails = true
                            }
                        }
                        HStack {
                            Button("Create Missing OCR Records") {
                                appState.createMissingOCRRecords()
                            }
                            Button("Re-run Failed OCR") {
                                appState.rerunFailedOCR()
                            }
                            Button("Reset Interrupted OCR") {
                                appState.resetProcessingOCRRecords()
                            }
                        }
                        HStack {
                            Button("Rebuild Search Index") {
                                appState.rebuildSearchIndex()
                            }
                            Button("Rebuild Duplicate Index") {
                                appState.rebuildDuplicateIndexFromMaintenance()
                            }
                        }
                        HStack {
                            Button("Clean Orphan Thumbnails") {
                                appState.cleanOrphanThumbnails()
                            }
                            Button("Clean Orphan Originals") {
                                confirmCleanOrphanOriginals = true
                            }
                            Button("Check Database") {
                                appState.checkDatabaseIntegrity()
                            }
                            Button("Vacuum Database") {
                                confirmVacuumDatabase = true
                            }
                        }
                    }
                    .disabled(appState.isMaintenanceRunning)

                    SettingsNote(text: "Orphan original cleanup never touches Desktop, Downloads, or any source folder outside the managed library.")
                }

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .alert("Rebuild all thumbnails?", isPresented: $confirmRebuildAllThumbnails) {
            Button("Rebuild All", role: .destructive) {
                appState.rebuildAllThumbnails()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This regenerates thumbnails for every managed screenshot with an existing original image.")
        }
        .alert("Clean orphan originals?", isPresented: $confirmCleanOrphanOriginals) {
            Button("Clean Orphan Originals", role: .destructive) {
                appState.cleanOrphanOriginals()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only files inside the Screenshot Inbox Library/Originals folder that are not referenced by the database will be removed.")
        }
        .alert("Vacuum database?", isPresented: $confirmVacuumDatabase) {
            Button("Vacuum", role: .destructive) {
                appState.vacuumDatabase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs SQLite VACUUM and ANALYZE. It can take a moment on large libraries.")
        }
    }
}

private struct LibraryHealthSummary: View {
    let report: LibraryIntegrityReport

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Library Health")
                .font(.system(size: 12, weight: .semibold))
            summaryLine("Screenshots", report.totalScreenshots)
            summaryLine("Missing managed files", report.missingOriginals)
            summaryLine("Missing small thumbnails", report.missingThumbnails)
            summaryLine("Missing large thumbnails", report.missingLargeThumbnails)
            summaryLine("Invalid image files", report.invalidImageFiles)
            summaryLine("Orphan thumbnails", report.orphanThumbnails)
            summaryLine("Orphan originals", report.orphanOriginals)
            summaryLine("Orphan database rows", report.orphanDatabaseRows)
            summaryLine("Missing OCR records", report.missingOCRRecords)
            Text("Search index: \(report.searchIndexOutOfDate ? "needs rebuild" : "not required")")
            Text("Duplicate index: \(report.duplicateIndexOutOfDate ? "needs rebuild" : "ok")")
            ForEach(report.warnings.prefix(3), id: \.self) { warning in
                Text(warning)
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.SemanticColor.label)
    }

    private func summaryLine(_ title: String, _ value: Int) -> some View {
        Text("\(title): \(value)")
    }
}

private struct SourceSyncStatusRow: View {
    let title: String
    let status: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            }
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.SemanticColor.divider.opacity(0.65), lineWidth: 1)
        )
    }
}
