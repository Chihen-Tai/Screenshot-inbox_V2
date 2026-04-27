import SwiftUI

struct SidebarItemView: View {
    let item: SidebarItem

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
        .contentShape(Rectangle())
    }
}
