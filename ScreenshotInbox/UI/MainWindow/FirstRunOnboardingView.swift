import SwiftUI

struct FirstRunOnboardingView: View {
    let onContinue: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to \(AppReleaseInfo.name)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.label)
                Text(AppReleaseInfo.shortDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            }

            VStack(alignment: .leading, spacing: 10) {
                onboardingLine("Creates a local managed library on this Mac.")
                onboardingLine("Screenshots and OCR text are not uploaded to any server.")
                onboardingLine("OCR and QR detection run locally using Apple frameworks.")
                onboardingLine("You choose which folders are watched for Auto Import in Settings.")
                onboardingLine("Original source files are not modified by default.")
            }

            HStack {
                Button("Open Settings") {
                    onOpenSettings()
                }
                Spacer()
                Button("Continue") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func onboardingLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(Theme.Palette.accent.opacity(0.75))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.SemanticColor.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
