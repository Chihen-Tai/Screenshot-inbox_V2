import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Layout") {
                Toggle("Show Inspector by default", isOn: $appState.preferences.inspectorVisibleByDefault)
                Toggle("Show Sidebar by default", isOn: $appState.preferences.sidebarVisibleByDefault)
                Button("Reset UI Layout") {
                    appState.resetLayoutPreferences()
                }
                SettingsNote(text: "Compact windows may still hide panels automatically so the grid remains usable.")
            }
            Spacer()
        }
        .padding(22)
    }
}
