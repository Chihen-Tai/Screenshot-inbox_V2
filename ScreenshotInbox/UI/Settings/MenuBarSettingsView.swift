import SwiftUI

struct MenuBarSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "Menu Bar") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            "Show Screenshot Inbox in menu bar",
                            isOn: preferenceBinding(\.menuBarEnabled)
                        )
                        .toggleStyle(.checkbox)

                        Toggle(
                            "Show new screenshot count badge",
                            isOn: preferenceBinding(\.menuBarBadgeEnabled)
                        )
                        .toggleStyle(.checkbox)
                        .disabled(!appState.screenshotInboxPreferences.menuBarEnabled)
                    }
                }
            }
            .padding(20)
        }
    }

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<ScreenshotInboxPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { appState.screenshotInboxPreferences[keyPath: keyPath] },
            set: { value in
                var preferences = appState.screenshotInboxPreferences
                preferences[keyPath: keyPath] = value
                appState.screenshotInboxPreferences = preferences
            }
        )
    }
}
