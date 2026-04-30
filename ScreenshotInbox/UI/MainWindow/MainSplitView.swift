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
    @State private var liveSidebarWidth: CGFloat?
    @State private var liveInspectorWidth: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let decision = MainSplitLayoutDecision(
                width: proxy.size.width,
                sidebarUserVisible: appState.sidebarOverrideVisible,
                inspectorUserVisible: appState.inspectorOverrideVisible,
                preferredSidebarWidth: liveSidebarWidth ?? appState.sidebarPanelWidth,
                preferredInspectorWidth: liveInspectorWidth ?? appState.inspectorPanelWidth
            )

            HStack(spacing: 0) {
                if decision.sidebarVisible {
                    SidebarView()
                        .frame(width: decision.sidebarWidth)
                    SplitDivider(
                        accessibilityLabel: "Resize sidebar",
                        onDragChanged: { translation in
                            let start = sidebarDragStartWidth ?? decision.sidebarWidth
                            if sidebarDragStartWidth == nil {
                                sidebarDragStartWidth = start
                                liveSidebarWidth = start
                                logSplitResize("begin sidebar width=\(format(start)) gridWidth=\(format(decision.gridWidth))")
                            }
                            let width = decision.clampedSidebarWidth(start + translation)
                            withTransaction(Transaction(animation: nil)) {
                                liveSidebarWidth = width
                            }
                        },
                        onDragEnded: {
                            let finalWidth = liveSidebarWidth ?? decision.sidebarWidth
                            appState.sidebarPanelWidth = finalWidth
                            logSplitResize("end sidebar width=\(format(finalWidth)) gridWidth=\(format(decision.gridWidth))")
                            sidebarDragStartWidth = nil
                            liveSidebarWidth = nil
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
                            if inspectorDragStartWidth == nil {
                                inspectorDragStartWidth = start
                                liveInspectorWidth = start
                                logSplitResize("begin inspector width=\(format(start)) gridWidth=\(format(decision.gridWidth))")
                            }
                            let width = decision.clampedInspectorWidth(start - translation)
                            withTransaction(Transaction(animation: nil)) {
                                liveInspectorWidth = width
                            }
                        },
                        onDragEnded: {
                            let finalWidth = liveInspectorWidth ?? decision.inspectorWidth
                            appState.inspectorPanelWidth = finalWidth
                            logSplitResize("end inspector width=\(format(finalWidth)) gridWidth=\(format(decision.gridWidth))")
                            inspectorDragStartWidth = nil
                            liveInspectorWidth = nil
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
                logLayout(MainSplitLayoutDecision(
                    width: newWidth,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: liveSidebarWidth ?? appState.sidebarPanelWidth,
                    preferredInspectorWidth: liveInspectorWidth ?? appState.inspectorPanelWidth
                ))
            }
            .onChange(of: appState.sidebarOverrideVisible) { _, _ in
                logLayout(MainSplitLayoutDecision(
                    width: proxy.size.width,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: liveSidebarWidth ?? appState.sidebarPanelWidth,
                    preferredInspectorWidth: liveInspectorWidth ?? appState.inspectorPanelWidth
                ))
            }
            .onChange(of: appState.inspectorOverrideVisible) { _, _ in
                logLayout(MainSplitLayoutDecision(
                    width: proxy.size.width,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: liveSidebarWidth ?? appState.sidebarPanelWidth,
                    preferredInspectorWidth: liveInspectorWidth ?? appState.inspectorPanelWidth
                ))
            }
            .onChange(of: appState.sidebarPanelWidth) { _, _ in
                logLayout(MainSplitLayoutDecision(
                    width: proxy.size.width,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: liveSidebarWidth ?? appState.sidebarPanelWidth,
                    preferredInspectorWidth: liveInspectorWidth ?? appState.inspectorPanelWidth
                ))
            }
            .onChange(of: appState.inspectorPanelWidth) { _, _ in
                logLayout(MainSplitLayoutDecision(
                    width: proxy.size.width,
                    sidebarUserVisible: appState.sidebarOverrideVisible,
                    inspectorUserVisible: appState.inspectorOverrideVisible,
                    preferredSidebarWidth: liveSidebarWidth ?? appState.sidebarPanelWidth,
                    preferredInspectorWidth: liveInspectorWidth ?? appState.inspectorPanelWidth
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

    private func logLayout(_ decision: MainSplitLayoutDecision) {
        #if DEBUG
        let summary = decision.debugSummary
        if summary != lastDebugSummary {
            print("[Layout] \(summary)")
            lastDebugSummary = summary
        }
        #endif
    }

    private func logSplitResize(_ message: String) {
        #if DEBUG
        print("[SplitResize] \(message)")
        #endif
    }

    private func format(_ value: CGFloat) -> String {
        guard value.isFinite else { return "invalid" }
        return String(format: "%.0f", Double(value))
    }
}

struct MainSplitLayoutDecision {
    let width: CGFloat
    let mode: Theme.LayoutMode
    let sidebarUserVisible: Bool
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
        self.sidebarUserVisible = sidebarUserVisible
        self.inspectorUserVisible = inspectorUserVisible

        let gridMin = MainSplitLayoutDecision.gridMinimum(for: mode)
        let dividerWidth = Theme.Layout.splitDividerWidth
        self.gridMin = gridMin
        self.dividerWidth = dividerWidth

        let wantsSidebar = sidebarUserVisible
        let sidebarCanFitAtMinimum = width - Theme.Layout.sidebarMin - dividerWidth >= gridMin
        self.sidebarVisible = wantsSidebar && mode != .compact && sidebarCanFitAtMinimum

        let sidebarMinimumBudget = sidebarVisible ? Theme.Layout.sidebarMin + dividerWidth : 0
        let wantsInspector = inspectorUserVisible && mode != .compact
        let inspectorCanFitAtMinimum = width - sidebarMinimumBudget - Theme.Layout.inspectorMin - dividerWidth >= gridMin
        self.inspectorVisible = wantsInspector && inspectorCanFitAtMinimum

        let sidebarMaxForLayout = width
            - gridMin
            - (sidebarVisible ? dividerWidth : 0)
            - (inspectorVisible ? Theme.Layout.inspectorMin + dividerWidth : 0)
        self.sidebarWidth = sidebarVisible
            ? MainSplitLayoutDecision.clamp(
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
            ? MainSplitLayoutDecision.clamp(
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
        "windowWidth=\(format(width)) mode=\(mode) userSidebarVisible=\(sidebarUserVisible) effectiveSidebarVisible=\(sidebarVisible) sidebarWidth=\(format(sidebarWidth)) userInspectorVisible=\(inspectorUserVisible) effectiveInspectorVisible=\(inspectorVisible) inspectorWidth=\(format(inspectorWidth)) gridWidth=\(format(gridWidth))"
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
    @State private var cursorPushed = false
    @GestureState private var isDragging = false

    var body: some View {
        Color.clear
            .frame(width: Theme.Layout.splitDividerWidth)
            .overlay {
                Rectangle()
                    .fill((isHovering || isDragging) ? Theme.Palette.accent.opacity(0.45) : Theme.SemanticColor.divider)
                    .frame(width: Theme.Layout.splitDividerVisibleWidth)
            }
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
            .onHover { hovering in
                isHovering = hovering
                if hovering, !cursorPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorPushed = true
                } else if !hovering, cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
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
