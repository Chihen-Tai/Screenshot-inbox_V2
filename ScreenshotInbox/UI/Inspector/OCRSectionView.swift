import SwiftUI

struct OCRSectionView: View {
    @EnvironmentObject private var appState: AppState
    let screenshot: Screenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "OCR")
                Spacer(minLength: 0)
                Button {
                    appState.router.copyOCRText([screenshot])
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Copy OCR Text")
                Button {
                    appState.router.rerunOCR([screenshot])
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Re-run OCR")
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.ocrResult(for: screenshot)?.status {
        case .pending:
            statusText("OCR pending")
        case .processing:
            statusText("Recognizing text...")
        case .failed:
            VStack(alignment: .leading, spacing: 5) {
                statusText("OCR failed")
                if let message = appState.ocrResult(for: screenshot)?.errorMessage {
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                        .lineLimit(3)
                    }
            }
        case .skipped:
            statusText("OCR skipped")
        case .complete:
            if screenshot.ocrSnippets.isEmpty {
                statusText("No text detected")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(screenshot.ocrSnippets.prefix(8).enumerated()), id: \.offset) { _, snippet in
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
                    if screenshot.ocrSnippets.count > 8 {
                        Text("\(screenshot.ocrSnippets.count - 8) more lines")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
                    }
                }
            }
        case nil:
            statusText("OCR not queued yet")
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.SemanticColor.secondaryLabel)
    }
}
