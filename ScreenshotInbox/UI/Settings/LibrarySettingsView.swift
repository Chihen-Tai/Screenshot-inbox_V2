import SwiftUI

struct LibrarySettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Library Location") {
                Text(appState.library.libraryRootURL.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack {
                    Button("Reveal Library in Finder") {
                        appState.revealLibraryInFinder()
                    }
                    Button("Check Library Integrity") {
                        appState.checkLibraryIntegrityPlaceholder()
                    }
                    Button("Change Library Location") {}
                        .disabled(true)
                        .help("Changing library location is planned for a later phase.")
                }
                SettingsNote(text: "Screenshot Inbox currently runs in Library Mode. Imported files are copied into this managed folder.")
            }
            Spacer()
        }
        .padding(22)
    }
}
