import SwiftUI

struct OCRSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Recognition Languages") {
                Picker("Preferred OCR Languages", selection: ocrPresetBinding) {
                    ForEach(OCRLanguagePreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.radioGroup)
                SettingsNote(text: "Current order: \(appState.preferences.ocrPreferredLanguages.joined(separator: ", ")). Changes affect future OCR jobs. Existing results are not re-run automatically.")
                Button("Re-run OCR for All Screenshots") {
                    appState.rerunOCR(for: appState.allScreenshots)
                }
            }
            Spacer()
        }
        .padding(22)
    }

    private var ocrPresetBinding: Binding<OCRLanguagePreset> {
        Binding(
            get: { appState.preferences.ocrLanguagePreset },
            set: { appState.setOCRLanguagePreset($0) }
        )
    }
}
