#if DEBUG
import SwiftUI

/// DEBUG-only bar that exposes the same selection methods Cmd-A and Escape
/// are supposed to drive. Lets us verify the selection-model + UI sync path
/// independently of keyboard event routing.
///
/// Click Debug Select All — if all items don't visually select, the bug is
/// in the selection / sync layer. If they do select, the bug is in keyboard
/// dispatch and these shortcut overrides need a different path.
struct DebugSelectionBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Text("DEBUG")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.25)))
                .foregroundStyle(Color.orange)

            Button("Select All") {
                print("[Debug] tap Select All")
                appState.selectAllVisibleScreenshots()
            }

            Button("Clear") {
                print("[Debug] tap Clear")
                appState.clearScreenshotSelection()
            }

            Button("Print State") {
                print("[Debug] tap Print State")
                appState.printSelectionState()
            }

            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.06))
    }
}
#endif
