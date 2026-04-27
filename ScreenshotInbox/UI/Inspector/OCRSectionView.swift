import SwiftUI

struct OCRSectionView: View {
    let screenshot: Screenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "OCR Snippets")
            if screenshot.ocrSnippets.isEmpty {
                Text(screenshot.isOCRComplete ? "No text detected" : "OCR pending")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(screenshot.ocrSnippets.enumerated()), id: \.offset) { _, snippet in
                        HStack(alignment: .top, spacing: 9) {
                            Rectangle()
                                .fill(Theme.SemanticColor.divider.opacity(0.55))
                                .frame(width: 2)
                                .cornerRadius(1)
                            Text(snippet)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.SemanticColor.label.opacity(0.85))
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
    }
}
