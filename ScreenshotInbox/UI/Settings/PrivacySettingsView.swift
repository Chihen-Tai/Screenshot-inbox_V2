import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "Privacy & Permissions") {
                    SettingsNote(text: AppPrivacyInfo.localFirstGuarantee)
                    SettingsNote(text: AppPrivacyInfo.noTelemetryStatement)
                    SettingsNote(text: AppPrivacyInfo.watchedFoldersStatement)
                    SettingsNote(text: AppPrivacyInfo.originalSourceSafetyStatement)
                }

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
                        Button("Open Privacy Document") {
                            appState.openPrivacyDocument()
                        }
                    }
                    SettingsNote(text: AppPrivacyInfo.managedLibraryDescription)
                }

                SettingsSection(title: "Auto Import") {
                    Toggle("Auto Import Enabled", isOn: $appState.isAutoImportEnabled)
                        .toggleStyle(.switch)
                    if appState.importSources.isEmpty {
                        SettingsNote(text: "No watched folders are configured.")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.importSources) { source in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(source.isEnabled ? Color.green.opacity(0.75) : Theme.SemanticColor.tertiaryLabel)
                                        .frame(width: 6, height: 6)
                                    Text(source.effectiveDisplayName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(source.folderPath)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                    SettingsNote(text: "Auto Import only watches configured folders. Existing files are imported only when you choose Scan Watched Folders Now.")
                }

                SettingsSection(title: "Sandbox Status") {
                    SettingsNote(text: AppPrivacyInfo.sandboxStatus)
                    SettingsNote(text: "Security-scoped bookmark handling is represented by FolderAccessService and can be expanded when a sandboxed release is planned.")
                }
            }
            .padding(22)
        }
    }
}
