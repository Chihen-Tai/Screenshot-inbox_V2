import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Appearance") {
                Picker("Appearance", selection: $appState.preferences.preferredAppearance) {
                    ForEach(PreferredAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                SettingsNote(text: "The appearance preference is saved and applied to Screenshot Inbox windows.")
            }
            SettingsSection(title: "Panels") {
                Toggle("Show Inspector by default", isOn: $appState.preferences.inspectorVisibleByDefault)
                Toggle("Show Sidebar by default", isOn: $appState.preferences.sidebarVisibleByDefault)
            }
            Spacer()
        }
        .padding(22)
    }
}
