import SwiftUI

struct DetectedCodesSectionView: View {
    @EnvironmentObject private var appState: AppState
    let screenshot: Screenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Detected Codes")
                Spacer(minLength: 0)
                Button {
                    appState.router.rerunCodeDetection([screenshot])
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Re-detect QR codes")
            }

            if codes.isEmpty {
                Text("No QR code detected")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(codes) { code in
                        codeRow(code)
                    }
                }
            }
        }
    }

    private var codes: [DetectedCode] {
        appState.detectedCodes(for: screenshot)
    }

    private func codeRow(_ code: DetectedCode) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(code.symbology)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            Text(code.payload)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.SemanticColor.label.opacity(0.88))
                .lineLimit(4)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                if code.isURL {
                    Button("Open Link") {
                        appState.openDetectedCode(code)
                    }
                    .buttonStyle(.plain)
                    Button("Copy Link") {
                        appState.copyDetectedCode(code)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Copy Text") {
                        appState.copyDetectedCode(code)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.Palette.accent)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.SemanticColor.quietFill.opacity(0.35))
        )
    }
}
