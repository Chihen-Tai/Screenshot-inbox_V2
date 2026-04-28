import SwiftUI

struct SidebarItemView: View {
    let item: SidebarItem
    var isDropTargeted: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .frame(width: 20)
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            Text(item.title)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.SemanticColor.label)
            Spacer(minLength: 0)
            if let count = item.count {
                Text("\(count)")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
            }
        }
        .padding(.vertical, Theme.Layout.sidebarRowVPadding)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isDropTargeted ? Theme.Palette.selectionFill : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Theme.Palette.selectionStroke.opacity(0.65) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
    }
}
