import SwiftUI

struct RenameSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Rename Behavior") {
                Toggle("Also rename original source files", isOn: $appState.preferences.renameOriginalSourceFiles)
                    .disabled(true)
                SettingsNote(text: "Default behavior renames the managed copy inside Screenshot Inbox. Original Desktop or Downloads files remain unchanged. Renaming original files needs permission and conflict handling and is planned for a later phase.")
            }
            Spacer()
        }
        .padding(22)
    }
}
