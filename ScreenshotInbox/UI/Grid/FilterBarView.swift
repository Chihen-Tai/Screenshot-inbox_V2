import SwiftUI

struct FilterBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appState.enabledQuickFilterChips, id: \.self) { chip in
                    FilterChipButton(
                        chip: chip,
                        isActive: appState.activeFilterChip == chip,
                        action: { appState.activeFilterChip = chip }
                    )
                }
            }
            .padding(.horizontal, Theme.Layout.filterBarHorizontalInset)
            .padding(.vertical, Theme.Layout.filterBarVerticalInset)
        }
        .onChange(of: appState.preferences.quickFilters) { _, _ in
            if !appState.enabledQuickFilterChips.contains(appState.activeFilterChip) {
                appState.activeFilterChip = .all
            }
        }
    }
}

private struct FilterChipButton: View {
    let chip: FilterChip
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(chip.rawValue)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(background)
                )
                .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isActive { return Theme.Palette.selectionFill }
        if isHovering { return Theme.SemanticColor.quietFill.opacity(0.9) }
        return Theme.SemanticColor.quietFill.opacity(0.5)
    }
    private var foreground: Color {
        isActive ? Theme.Palette.accent : Theme.SemanticColor.label.opacity(0.78)
    }
}
