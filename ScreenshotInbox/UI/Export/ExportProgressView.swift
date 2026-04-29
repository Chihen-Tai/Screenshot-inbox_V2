import SwiftUI

struct ExportProgressView: View {
    let isExporting: Bool

    var body: some View {
        if isExporting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Exporting PDF...")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            }
        }
    }
}
