import SwiftUI
import AppKit

/// Mode-adaptive split layout.
///
/// The active mode is decided by a `GeometryReader` here (not in the window
/// view) so the measurement reflects the actual content area, not the window
/// frame minus chrome. The panes are laid out explicitly instead of via
/// `NavigationSplitView` so hidden side panes do not keep stale column widths
/// during live window resizing.
struct MainSplitView: View {
    @EnvironmentObject private var appState: AppState
    @State private var lastDebugSummary: String = ""
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var inspectorDragStartWidth: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let decision = LayoutDecision(
                width: proxy.size.width,
                sidebarUserVisible: appState.sidebarOverrideVisible,
                inspectorUserVisible: appState.inspectorOverrideVisible,
                preferredSidebarWidth: appState.sidebarPanelWidth,
                preferredInspectorWidth: appState.inspectorPanelWidth
            )

            HStack(spacing: 0) {
                if decision.sidebarVisible {
                    SidebarView()
                        .frame(width: decision.sidebarWidth)
                    SplitDivider(
                        accessibilityLabel: "Resize sidebar",
                        onDragChanged: { translation in
                            let start = sidebarDragStartWidth ?? decision.sidebarWidth
                            sidebarDragStartWidth = start
                            appState.sidebarPanelWidth = decision.clampedSidebarWidth(start + translation)
                        },
                        onDragEnded: {
                            sidebarDragStartWidth = nil
                        }
                    )
                }

                ScreenshotGridContainer()
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

                if decision.inspectorVisible {
                    SplitDivider(
                        accessibilityLabel: "Resize inspector",
                        onDragChanged: { translation in
                            let start = inspectorDragStartWidth ?? decision.inspectorWidth
                            inspectorDragStartWidth = start
                            appState.inspectorPanelWidth = decision.clampedInspectorWidth(start - translation)
                        },
                        onDragEnded: {
                            inspectorDragStartWidth = nil
                        }
                    )
                    InspectorView()
                        .frame(width: decision.inspectorWidth)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .onAppear {
                updateMode(width: proxy.size.width)
                logLayout(decision)
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                updateMode(width: newWidth)
                logLayout(LayoutDecision(
                    width: newWidth,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: appState.sidebarPanelWidth,
                    preferredInspectorWidth: appState.inspectorPanelWidth
                ))
            }
            .onChange(of: appState.sidebarOverrideVisible) { _, _ in
                logLayout(LayoutDecision(
                    width: proxy.size.width,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: appState.sidebarPanelWidth,
                    preferredInspectorWidth: appState.inspectorPanelWidth
                ))
            }
            .onChange(of: appState.inspectorOverrideVisible) { _, _ in
                logLayout(LayoutDecision(
                    width: proxy.size.width,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: appState.sidebarPanelWidth,
                    preferredInspectorWidth: appState.inspectorPanelWidth
                ))
            }
            .onChange(of: appState.sidebarPanelWidth) { _, _ in
                logLayout(LayoutDecision(
                    width: proxy.size.width,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: appState.sidebarPanelWidth,
                    preferredInspectorWidth: appState.inspectorPanelWidth
                ))
            }
            .onChange(of: appState.inspectorPanelWidth) { _, _ in
                logLayout(LayoutDecision(
                    width: proxy.size.width,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: appState.sidebarPanelWidth,
                    preferredInspectorWidth: appState.inspectorPanelWidth
                ))
            }
        }
    }

    private func updateMode(width: CGFloat) {
        let next = Theme.LayoutMode.from(width: width)
        if appState.layoutMode != next {
            print("[MainSplitView] layoutMode \(appState.layoutMode) → \(next) at width=\(Int(width))")
            appState.layoutMode = next
        }
    }

    private func logLayout(_ decision: LayoutDecision) {
        #if DEBUG
        let summary = decision.debugSummary
        if summary != lastDebugSummary {
            print("[Layout] \(summary)")
            lastDebugSummary = summary
        }
        #endif
    }
}

private struct LayoutDecision {
    let width: CGFloat
    let mode: Theme.LayoutMode
    let sidebarVisible: Bool
    let sidebarWidth: CGFloat
    let inspectorUserVisible: Bool
    let inspectorVisible: Bool
    let inspectorWidth: CGFloat
    let gridWidth: CGFloat
    private let gridMin: CGFloat
    private let dividerWidth: CGFloat

    init(
        width: CGFloat,
        sidebarUserVisible: Bool,
        inspectorUserVisible: Bool,
        preferredSidebarWidth: CGFloat,
        preferredInspectorWidth: CGFloat
    ) {
        self.width = max(0, width)
        self.mode = Theme.LayoutMode.from(width: width)
        self.inspectorUserVisible = inspectorUserVisible

        let gridMin = LayoutDecision.gridMinimum(for: mode)
        let dividerWidth = Theme.Layout.splitDividerWidth
        self.gridMin = gridMin
        self.dividerWidth = dividerWidth

        let wantsSidebar = sidebarUserVisible
        let sidebarCanFitAtMinimum = width - Theme.Layout.sidebarMin - dividerWidth >= gridMin
        self.sidebarVisible = wantsSidebar && sidebarCanFitAtMinimum

        let sidebarMinimumBudget = sidebarVisible ? Theme.Layout.sidebarMin + dividerWidth : 0
        let wantsInspector = inspectorUserVisible && mode != .compact
        let inspectorCanFitAtMinimum = width - sidebarMinimumBudget - Theme.Layout.inspectorMin - dividerWidth >= gridMin
        self.inspectorVisible = wantsInspector && inspectorCanFitAtMinimum

        let sidebarMaxForLayout = width
            - gridMin
            - (sidebarVisible ? dividerWidth : 0)
            - (inspectorVisible ? Theme.Layout.inspectorMin + dividerWidth : 0)
        self.sidebarWidth = sidebarVisible
            ? LayoutDecision.clamp(
                preferredSidebarWidth,
                min: Theme.Layout.sidebarMin,
                max: min(Theme.Layout.sidebarMax, sidebarMaxForLayout)
            )
            : 0

        let inspectorMaxForLayout = width
            - gridMin
            - (sidebarVisible ? self.sidebarWidth + dividerWidth : 0)
            - (inspectorVisible ? dividerWidth : 0)
        self.inspectorWidth = inspectorVisible
            ? LayoutDecision.clamp(
                preferredInspectorWidth,
                min: Theme.Layout.inspectorMin,
                max: min(Theme.Layout.inspectorMax, inspectorMaxForLayout)
            )
            : 0
        self.gridWidth = max(
            0,
            width
            - self.sidebarWidth
            - self.inspectorWidth
            - (sidebarVisible ? dividerWidth : 0)
            - (inspectorVisible ? dividerWidth : 0)
        )
    }

    var debugSummary: String {
        "width=\(format(width)) mode=\(mode) sidebar=\(sidebarVisible) sidebarWidth=\(format(sidebarWidth)) inspectorUser=\(inspectorUserVisible) inspectorEffective=\(inspectorVisible) inspectorWidth=\(format(inspectorWidth)) gridWidth=\(format(gridWidth))"
    }

    func clampedSidebarWidth(_ proposed: CGFloat) -> CGFloat {
        let maxWidth = width
            - gridMin
            - dividerWidth
            - (inspectorVisible ? Theme.Layout.inspectorMin + dividerWidth : 0)
        return Self.clamp(proposed, min: Theme.Layout.sidebarMin, max: min(Theme.Layout.sidebarMax, maxWidth))
    }

    func clampedInspectorWidth(_ proposed: CGFloat) -> CGFloat {
        let maxWidth = width
            - gridMin
            - dividerWidth
            - (sidebarVisible ? sidebarWidth + dividerWidth : 0)
        return Self.clamp(proposed, min: Theme.Layout.inspectorMin, max: min(Theme.Layout.inspectorMax, maxWidth))
    }

    private static func gridMinimum(for mode: Theme.LayoutMode) -> CGFloat {
        switch mode {
        case .regular:
            return Theme.Layout.gridUsableMinRegular
        case .medium:
            return Theme.Layout.gridUsableMinMedium
        case .compact:
            return Theme.Layout.gridUsableMinCompact
        }
    }

    private func format(_ value: CGFloat) -> String {
        guard value.isFinite else { return "invalid" }
        return String(format: "%.0f", Double(value))
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        let safeMaximum = Swift.max(minimum, maximum)
        return Swift.min(Swift.max(value, minimum), safeMaximum)
    }
}

private struct SplitDivider: View {
    let accessibilityLabel: String
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    @State private var isHovering = false
    @GestureState private var isDragging = false

    var body: some View {
        Rectangle()
            .fill((isHovering || isDragging) ? Theme.Palette.accent.opacity(0.45) : Theme.SemanticColor.divider)
            .frame(width: Theme.Layout.splitDividerVisibleWidth)
            .frame(width: Theme.Layout.splitDividerWidth)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        onDragChanged(value.translation.width)
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
    }
}
