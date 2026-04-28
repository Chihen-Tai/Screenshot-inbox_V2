import SwiftUI
import AppKit

struct ImportSourceSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if appState.importSources.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appState.importSources) { source in
                            ImportSourceRow(source: source)
                                .environmentObject(appState)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(22)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Auto Import")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Toggle("Enabled", isOn: $appState.isAutoImportEnabled)
                    .toggleStyle(.switch)
            }
            Text("Watch folders for new screenshots. Existing files are only imported when you scan manually.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No watched folders")
                .font(.system(size: 13, weight: .medium))
            Text("Add Desktop or another screenshot folder when you want Screenshot Inbox to watch it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.SemanticColor.quietFill.opacity(0.45))
        )
    }

    private var actions: some View {
        HStack {
            Button {
                presentFolderPicker()
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
            Button {
                appState.scanWatchedFoldersNow()
            } label: {
                Label("Scan Watched Folders Now", systemImage: "arrow.clockwise")
            }
            .disabled(!appState.isAutoImportEnabled || appState.importSources.filter(\.isEnabled).isEmpty)
            Spacer()
        }
    }

    private func presentFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to watch for new screenshots"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        appState.addImportSource(folderURL: url)
    }
}

private struct ImportSourceRow: View {
    @EnvironmentObject private var appState: AppState
    let source: ImportSource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 16))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.effectiveDisplayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.SemanticColor.label)
                Text(source.folderPath)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { source.isEnabled },
                set: { appState.setImportSourceEnabled(source, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            Button {
                appState.deleteImportSource(source)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            .help("Remove")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.SemanticColor.quietFill.opacity(0.35))
        )
    }
}
