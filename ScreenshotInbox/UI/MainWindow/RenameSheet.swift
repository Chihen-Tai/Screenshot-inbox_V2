import SwiftUI

/// Phase 5 — modal sheet for renaming a single screenshot.
/// Bound to `AppState.pendingRenameText`; commit/cancel funnel through
/// `AppState.commitRename` / `cancelRename` so the rest of the app sees
/// the new name through the existing `objectWillChange` plumbing.
struct RenameSheet: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var fieldFocused: Bool

    let originalName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Screenshot")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.SemanticColor.label)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                TextField("", text: $appState.pendingRenameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($fieldFocused)
                    .onSubmit { appState.commitRename() }
                Text("This renames the copy inside Screenshot Inbox. The original file is unchanged.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { appState.cancelRename() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { appState.commitRename() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || trimmed == originalName)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { fieldFocused = true }
    }

    private var trimmed: String {
        appState.pendingRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
