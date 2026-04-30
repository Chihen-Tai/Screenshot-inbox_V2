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
                    SettingsNote(text: "By default, Screenshot Inbox works in Library Mode. Imported files are copied into a managed library. When Source Folder Sync is enabled, selected actions can also update the original Desktop, Downloads, or watched-folder files.")

                    VStack(alignment: .leading, spacing: 8) {
                        SourceSyncToggleRow(
                            title: "Rename original source files when renaming screenshots",
                            detail: "When enabled, renaming in Screenshot Inbox will also rename the original file if it still exists.",
                            isOn: $appState.preferences.syncRenameOriginalSourceFiles
                        )
                        SourceSyncToggleRow(
                            title: "Move original source files to macOS Trash when moving screenshots to Screenshot Inbox Trash",
                            detail: "When enabled, app Trash also moves the original source file to macOS Trash. It is not permanently deleted.",
                            isOn: $appState.preferences.syncMoveOriginalToTrashOnAppTrash
                        )
                        SourceSyncToggleRow(
                            title: "Move original source files to macOS Trash when permanently deleting screenshots",
                            detail: "When enabled, permanent deletion of managed copies also asks to move original source files to macOS Trash.",
                            isOn: $appState.preferences.syncMoveOriginalToTrashOnPermanentDelete
                        )
                        SourceSyncToggleRow(
                            title: "Move Screenshot Inbox items to Trash when original source files are deleted",
                            detail: "When enabled, if the original Desktop, Downloads, or watched-folder file is deleted outside Screenshot Inbox, the matching item will be moved to Screenshot Inbox Trash.",
                            isOn: $appState.preferences.syncTrashInboxItemWhenOriginalDeleted
                        )
                        SourceSyncToggleRow(
                            title: "Update Screenshot Inbox item name when original source file is renamed",
                            detail: "When enabled, Screenshot Inbox reconciles same-folder source renames by file hash and updates the linked source path and item name.",
                            isOn: $appState.preferences.syncRenameInboxItemWhenOriginalRenamed
                        )
                        HStack {
                            Button("Check Source Sync Now") {
                                appState.checkSourceFileStatus()
                            }
                            .disabled(!appState.preferences.syncTrashInboxItemWhenOriginalDeleted &&
                                      !appState.preferences.syncRenameInboxItemWhenOriginalRenamed)
                            Spacer()
                        }
                        SourceSyncToggleRow(
                            title: "Copy newly added screenshots to a default source folder",
                            detail: "When enabled, pasted or generated imports without a stable source file are copied to the selected folder.",
                            isOn: $appState.preferences.copyNewImportsToDefaultSourceFolder
                        )
                        HStack {
                            Text(appState.preferences.defaultSourceFolderPath)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Choose Folder...") {
                                appState.chooseDefaultSourceFolder()
                            }
                        }
                        .disabled(!appState.preferences.copyNewImportsToDefaultSourceFolder)
                    }

                    SettingsNote(text: "Screenshot Inbox never permanently deletes original source files in this phase. Source-file removal uses macOS Trash.")
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

private struct SourceSyncToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(title, isOn: $isOn)
                    .font(.system(size: 12, weight: .medium))
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
