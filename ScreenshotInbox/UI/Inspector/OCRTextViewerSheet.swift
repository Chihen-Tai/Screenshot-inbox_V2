import SwiftUI

struct OCRTextViewerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let screenshot: Screenshot

    private var ocrText: String {
        screenshot.ocrSnippets.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("OCR Text")
                    .font(.title3.weight(.semibold))
                Text(screenshot.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            SelectableTextView(
                text: ocrText,
                font: .systemFont(ofSize: 13)
            )
            .frame(minWidth: 640, idealWidth: 720, maxWidth: .infinity,
                   minHeight: 360, idealHeight: 460, maxHeight: .infinity)
            .padding(12)
            .background(Theme.SemanticColor.underPanel.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.SemanticColor.divider.opacity(0.6), lineWidth: 1)
            }

            HStack {
                Spacer()
                Button("Copy All") {
                    appState.router.copyOCRText([screenshot])
                }
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 700, idealWidth: 760, minHeight: 500, idealHeight: 560)
    }
}
