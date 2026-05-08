import SwiftUI

struct ScreenshotSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "Screenshot Capture") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            "Automatically add new screenshots to Inbox",
                            isOn: preferenceBinding(\.autoCaptureEnabled)
                        )
                        .toggleStyle(.checkbox)

                        Text(appState.phase1ScreenshotFolderURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            Button("Choose Folder…") {
                                appState.choosePhase1ScreenshotFolder()
                            }
                            Button("Use Desktop") {
                                appState.useDesktopPhase1ScreenshotFolder()
                            }
                        }
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
