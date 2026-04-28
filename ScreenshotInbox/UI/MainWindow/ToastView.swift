import SwiftUI

/// Phase 5 — bottom-trailing transient banner. Shape echoes macOS's
/// "Now Playing" / Notification look: rounded ultra-thin material, subtle
/// shadow, single line of copy with an icon. Auto-dismiss is owned by
/// `AppState.showToast`; this view is a pure renderer.
struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
            Text(message.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.SemanticColor.label)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.SemanticColor.divider.opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.20), radius: 14, y: 4)
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var iconName: String {
        switch message.kind {
        case .info:        return "info.circle.fill"
        case .success:     return "checkmark.circle.fill"
        case .comingSoon:  return "sparkles"
        }
    }

    private var accent: Color {
        switch message.kind {
        case .info:        return Theme.Palette.accent
        case .success:     return Color.green
        case .comingSoon:  return Theme.SemanticColor.secondaryLabel
        }
    }
}
