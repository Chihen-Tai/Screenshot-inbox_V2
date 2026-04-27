import SwiftUI

/// Small uppercase header for sidebar groups. Slightly lighter than the
/// inspector's `SectionHeader` so the sidebar reads as quieter.
struct SidebarSectionView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
            .padding(.top, 6)
            .padding(.bottom, 1)
    }
}
