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
                VStack(alignment: .leading, spacing: 10) {
                    Text(screenshot.ocrSnippets.joined(separator: "\n"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.SemanticColor.label.opacity(0.85))
                        .lineSpacing(2)
                        .lineLimit(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 11)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Theme.SemanticColor.divider.opacity(0.55))
                                .frame(width: 2)
                                .cornerRadius(1)
                        }

                    HStack(spacing: 8) {
                        Button("Copy All") {
                            appState.router.copyOCRText([screenshot])
                        }
                        Button("View Full Text") {
                            appState.beginOCRTextViewer(for: screenshot)
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
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
