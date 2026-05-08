import SwiftUI

struct FloatingPreviewSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                SettingsSection(title: "Floating Preview") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "Enable floating preview",
                            isOn: preferenceBinding(
                                \.floatingPreviewEnabled,
                                log: { "[Settings] floatingPreviewEnabled changed to \($0)" }
                            )
                        )
                        .toggleStyle(.checkbox)

                        SettingsNote(text: "Master switch. When off, the floating preview never appears automatically.")

                        Toggle(
                            "Automatically show floating preview after screenshot",
                            isOn: preferenceBinding(
                                \.floatingPreviewAutoShowEnabled,
                                log: { "[Settings] floatingPreviewAutoShowEnabled changed to \($0)" }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .disabled(!appState.screenshotInboxPreferences.floatingPreviewEnabled)

                        HStack {
                            Text("Preview delay")
                            Spacer()
                            Stepper(
                                value: preferenceBinding(
                                    \.floatingPreviewDelay,
                                    log: { "[Settings] floatingPreviewDelay changed to \($0)" }
                                ),
                                in: 0.5...5.0,
                                step: 0.5
                            ) {
                                Text("\(appState.screenshotInboxPreferences.floatingPreviewDelay, specifier: "%.1f") sec")
                                    .monospacedDigit()
                                    .frame(minWidth: 48, alignment: .trailing)
                            }
                        }
                        .disabled(!appState.screenshotInboxPreferences.floatingPreviewEnabled
                                  || !appState.screenshotInboxPreferences.floatingPreviewAutoShowEnabled)
                    }
                }

                SettingsSection(title: "Display") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "Show multiple screenshots in floating preview",
                            isOn: preferenceBinding(\.showMultipleScreenshotsInFloatingPreview)
                        )
                        .toggleStyle(.checkbox)

                        HStack {
                            Text("Max visible screenshots")
                            Spacer()
                            Stepper(
                                value: preferenceBinding(\.maxFloatingPreviewItems),
                                in: 1...20
                            ) {
                                Text("\(appState.screenshotInboxPreferences.maxFloatingPreviewItems)")
                                    .monospacedDigit()
                                    .frame(minWidth: 28, alignment: .trailing)
                            }
                        }
                        .disabled(!appState.screenshotInboxPreferences.showMultipleScreenshotsInFloatingPreview)
                    }
                }

                SettingsSection(title: "Behaviour") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "Keep floating preview open while collecting screenshots",
                            isOn: preferenceBinding(
                                \.keepFloatingPreviewOpenWhileCollecting,
                                log: { "[Settings] keepFloatingPreviewOpenWhileCollecting changed to \($0)" }
                            )
                        )
                        .toggleStyle(.checkbox)

                        SettingsNote(
                            text: "When on, an already-open preview updates in place as new screenshots arrive instead of re-stealing focus."
                        )

                        Toggle(
                            "Allow opening empty floating preview",
                            isOn: preferenceBinding(
                                \.allowEmptyFloatingPreview,
                                log: { "[Settings] allowEmptyFloatingPreview changed to \($0)" }
                            )
                        )
                        .toggleStyle(.checkbox)

                        SettingsNote(
                            text: "When on, you can manually open the preview even with no new screenshots — it shows \"Waiting for screenshots…\"."
                        )
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Binding helpers

    private func preferenceBinding<Value>(
        _ keyPath: WritableKeyPath<ScreenshotInboxPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { appState.screenshotInboxPreferences[keyPath: keyPath] },
            set: { value in
                var prefs = appState.screenshotInboxPreferences
                prefs[keyPath: keyPath] = value
                appState.screenshotInboxPreferences = prefs
            }
        )
    }

    private func preferenceBinding<Value>(
        _ keyPath: WritableKeyPath<ScreenshotInboxPreferences, Value>,
        log: @escaping (Value) -> String
    ) -> Binding<Value> {
        Binding(
            get: { appState.screenshotInboxPreferences[keyPath: keyPath] },
            set: { value in
                print(log(value))
                var prefs = appState.screenshotInboxPreferences
                prefs[keyPath: keyPath] = value
                appState.screenshotInboxPreferences = prefs
            }
        )
    }
}
