import SwiftUI

#if DEBUG
struct AdvancedSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Developer Options") {
                Toggle("Show debug controls in main window", isOn: $appState.preferences.showDebugControls)
                Button("Print AppState") {
                    print("[Settings] AppState instance=\(ObjectIdentifier(appState)) screenshots=\(appState.allScreenshots.count) selected=\(appState.selectionCount)")
                }
                Button("Scan Watched Folders Now") {
                    appState.scanWatchedFoldersNow()
                }
                Button("Re-run OCR Queue") {
                    appState.rerunOCR(for: appState.allScreenshots)
                }
                Button("Rebuild Duplicate Index") {
                    appState.rebuildDuplicateIndex()
                }
                Button("Print Duplicate Groups") {
                    appState.printDuplicateGroups()
                }
                Button("Rebuild Search Index") {
                    appState.rebuildSearchIndex()
                }
            }
            Spacer()
        }
        .padding(22)
    }
}
#endif
