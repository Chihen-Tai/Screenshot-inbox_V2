import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PDFExportSheet: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ExportOptionsView(options: $appState.pdfExportOptions)
            filename
            destination
            Toggle("Add exported PDF back to library", isOn: $appState.pdfExportOptions.addBackToLibrary)
                .disabled(true)
                .help("PDF library import is planned for a later phase.")
            ExportProgressView(isExporting: appState.isPDFExporting)
            HStack {
                Spacer()
                Button("Cancel") { appState.cancelPDFExport() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(appState.isPDFExporting)
                Button("Export") {
                    Task { await appState.exportPDF() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isPDFExporting || appState.pdfExportOptions.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export PDF")
                .font(.system(size: 17, weight: .semibold))
            Text("\(appState.pdfExportTargetCount) screenshot\(appState.pdfExportTargetCount == 1 ? "" : "s") selected")
                .font(.system(size: 12))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
        }
    }

    private var filename: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("File Name")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            TextField("", text: filenameBinding)
                .textFieldStyle(.roundedBorder)
                .disabled(appState.isPDFExporting)
        }
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Destination")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            HStack {
                Text(appState.pdfExportOptions.outputPath)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Theme.SemanticColor.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Choose...") { chooseDestination() }
                    .disabled(appState.isPDFExporting)
            }
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = URL(fileURLWithPath: appState.pdfExportOptions.outputPath).lastPathComponent
        panel.directoryURL = URL(fileURLWithPath: appState.pdfExportOptions.outputPath).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var path = url.path
        if !path.lowercased().hasSuffix(".pdf") {
            path += ".pdf"
        }
        appState.pdfExportOptions.outputPath = path
    }

    private var filenameBinding: Binding<String> {
        Binding(
            get: {
                URL(fileURLWithPath: appState.pdfExportOptions.outputPath).lastPathComponent
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let currentURL = URL(fileURLWithPath: appState.pdfExportOptions.outputPath)
                var filename = trimmed
                if !filename.lowercased().hasSuffix(".pdf") {
                    filename += ".pdf"
                }
                appState.pdfExportOptions.outputPath = currentURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(filename)
                    .path
            }
        )
    }
}
