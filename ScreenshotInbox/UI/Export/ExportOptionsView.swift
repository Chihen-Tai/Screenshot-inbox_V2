import SwiftUI

struct ExportOptionsView: View {
    @Binding var options: PDFExportOptions

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            row("Page Size") {
                Picker("", selection: $options.pageSize) {
                    ForEach(PDFPageSize.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
            }
            row("Orientation") {
                Picker("", selection: $options.orientation) {
                    ForEach(PDFOrientation.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
            }
            row("Margins") {
                Picker("", selection: $options.margins) {
                    ForEach(PDFMargin.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
            }
            row("Image Fit") {
                Picker("", selection: $options.imageFit) {
                    ForEach(PDFImageFit.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
            }
            row("Order") {
                Picker("", selection: $options.order) {
                    ForEach(PDFExportOrder.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
            }
        }
        .pickerStyle(.menu)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            content()
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
