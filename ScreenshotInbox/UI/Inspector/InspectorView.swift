import SwiftUI

enum InspectorSection: Hashable {
    case preview
    case actions
    case metadata
    case ocr
    case detectedCodes
    case tags
    case selectionSummary
    case commonTags

    static let singleSelectionOrder: [InspectorSection] = [
        .preview,
        .actions,
        .ocr,
        .detectedCodes,
        .tags,
        .metadata
    ]

    static let multiSelectionOrder: [InspectorSection] = [
        .selectionSummary,
        .actions,
        .commonTags
    ]
}

/// Three-state inspector:
/// - none -> calm "no selection" message.
/// - one  -> preview, actions, metadata, OCR, detected codes, tags.
/// - many → multi-selection summary + batch actions stub.
struct InspectorView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch state {
            case .none:
                emptyState
            case .single(let shot):
                singleState(shot)
            case .multi(let shots):
                multiState(shots)
            }
        }
        // Force the inspector content to fill its column. Without this,
        // `ContentUnavailableView` (used by the empty state) reports its
        // intrinsic width, which can pull the column wider than the band
        // we set below. Filling first, then constraining via the column
        // width modifier, keeps the inspector pinned at its declared width.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(
            min: Theme.Layout.inspectorMin,
            ideal: Theme.Layout.inspectorIdeal,
            max: Theme.Layout.inspectorMax
        )
        .onAppear {
            print("[Inspector] onAppear; appState instance=\(ObjectIdentifier(appState)); selected count:", appState.selectedScreenshots.count)
        }
        .onChange(of: appState.selection.count) { _, newValue in
            print("[Inspector] selected count:", newValue)
        }
    }

    private enum InspectorState {
        case none
        case single(Screenshot)
        case multi([Screenshot])
    }

    private var state: InspectorState {
        let shots = appState.selectedScreenshots
        switch shots.count {
        case 0:  return .none
        case 1:  return .single(shots[0])
        default: return .multi(shots)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView(
            "No Screenshot Selected",
            systemImage: "sidebar.right",
            description: Text("Select a screenshot to view details.")
        )
    }

    // MARK: - Single

    private func singleState(_ shot: Screenshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.inspectorSectionSpacing) {
                let sections = InspectorSection.singleSelectionOrder
                ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                    singleSelectionSection(section, screenshot: shot)
                    if index < sections.count - 1 {
                        InspectorSeparator()
                    }
                }
            }
            .padding(Theme.Layout.inspectorPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func singleSelectionSection(_ section: InspectorSection, screenshot shot: Screenshot) -> some View {
        switch section {
        case .preview:
            PreviewBlock(screenshot: shot, thumbnailProvider: appState.thumbnailProvider)
        case .actions:
            ActionsSectionView(screenshot: shot)
        case .metadata:
            MetadataSectionView(
                screenshot: shot,
                originalPath: shot.originalPath
            )
        case .ocr:
            OCRSectionView(screenshot: shot)
        case .detectedCodes:
            DetectedCodesSectionView(screenshot: shot)
        case .tags:
            TagsSectionView(screenshot: shot)
        case .selectionSummary, .commonTags:
            EmptyView()
        }
    }

    // MARK: - Multi

    private func multiState(_ shots: [Screenshot]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.inspectorSectionSpacing) {
                let sections = InspectorSection.multiSelectionOrder
                ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                    multiSelectionSection(section, screenshots: shots)
                    if index < sections.count - 1 {
                        InspectorSeparator()
                    }
                }
            }
            .padding(Theme.Layout.inspectorPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func multiSelectionSection(_ section: InspectorSection, screenshots shots: [Screenshot]) -> some View {
        switch section {
        case .selectionSummary:
            MultiSelectionHeader(shots: shots)
        case .actions:
            MultiActionsSection()
        case .commonTags:
            CommonTagsSection(shots: shots)
        case .preview, .metadata, .ocr, .detectedCodes, .tags:
            EmptyView()
        }
    }
}

/// Hairline divider used between inspector sections.
struct InspectorSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.SemanticColor.divider.opacity(0.45))
            .frame(height: 0.5)
    }
}

private struct PreviewBlock: View {
    let screenshot: Screenshot
    let thumbnailProvider: MacThumbnailProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Preview")
            ScreenshotPreviewImageView(
                screenshot: screenshot,
                thumbnailProvider: thumbnailProvider
            )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.preview, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.preview, style: .continuous)
                        .strokeBorder(Theme.SemanticColor.divider.opacity(0.35), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Multi-selection sections

private struct MultiSelectionHeader: View {
    let shots: [Screenshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Selection")
            VStack(alignment: .leading, spacing: 4) {
                Text("\(shots.count) screenshots selected")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.SemanticColor.label)
                Text(totalSizeText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            }
        }
    }

    private var totalSizeText: String {
        let total = shots.reduce(0) { $0 + $1.byteSize }
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
        return "Total \(formatted)"
    }
}

private struct CommonTagsSection: View {
    let shots: [Screenshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Common Tags")
            if commonTags.isEmpty {
                Text("No tags shared")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SemanticColor.secondaryLabel)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(commonTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.Palette.accent.opacity(0.12)))
                            .overlay(
                                Capsule().strokeBorder(
                                    Theme.Palette.accent.opacity(0.20), lineWidth: 0.5
                                )
                            )
                            .foregroundStyle(Theme.Palette.accent.opacity(0.95))
                    }
                }
            }
        }
    }

    /// Tags present in every selected screenshot.
    private var commonTags: [String] {
        guard let first = shots.first else { return [] }
        var set = Set(first.tags)
        for s in shots.dropFirst() {
            set.formIntersection(s.tags)
        }
        return set.sorted()
    }
}

private struct MultiActionsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Actions")
            VStack(spacing: 0) {
                row(title: "Merge PDF", systemImage: "doc.on.doc") {
                    appState.router.mergeIntoPDF(appState.selectedScreenshots)
                }
                rowDivider
                row(title: "Export Originals", systemImage: "square.and.arrow.up") {
                    appState.router.exportOriginals(appState.selectedScreenshots)
                }
                rowDivider
                row(title: "Share", systemImage: "square.and.arrow.up.on.square") {
                    appState.router.share(appState.selectedScreenshots)
                }
                rowDivider
                row(title: "Copy OCR Text", systemImage: "text.viewfinder") {
                    appState.router.copyOCRText(appState.selectedScreenshots)
                }
                rowDivider
                row(title: "Add Tag", systemImage: "tag") {
                    appState.router.addTag(appState.selectedScreenshots)
                }
                rowDivider
                row(title: "Move to Collection", systemImage: "folder") {
                    appState.router.moveToCollection(appState.selectedScreenshots)
                }
                rowDivider
                row(title: "Move to Trash", systemImage: "trash", isDestructive: true) {
                    appState.router.moveToTrash(appState.selectedScreenshots)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Theme.SemanticColor.quietFill.opacity(0.35))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
    }

    private func row(title: String,
                     systemImage: String,
                     isDestructive: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(isDestructive
                                     ? Color.red.opacity(0.65)
                                     : Theme.SemanticColor.secondaryLabel)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(isDestructive
                                     ? Color.red.opacity(0.78)
                                     : Theme.SemanticColor.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.SemanticColor.divider.opacity(0.35))
            .frame(height: 0.5)
            .padding(.leading, 36)
    }
}
