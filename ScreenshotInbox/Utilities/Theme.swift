import SwiftUI

/// Centralized design tokens for the Phase 3.5 polish pass.
/// Keep palette aligned with the system accent color so the app respects
/// user preferences and adapts to dark / light mode automatically.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 9
        static let thumb: CGFloat = 8
        static let preview: CGFloat = 10
        static let panel: CGFloat = 10
        static let pill: CGFloat = 999
    }

    /// Layout constants used by SwiftUI views.
    /// AppKit-only constants for the collection layout live in `Layout.Grid`.
    enum Layout {
        // MARK: Window
        /// Bottom of the supported window-size range. Set to support
        /// quarter-screen usage on a 1440×900 display (≈720×450). Height
        /// floors at 560 so the toolbar + filter bar + a couple of grid rows
        /// remain visible.
        static let minWindowWidth: CGFloat = 720
        static let minWindowHeight: CGFloat = 560

        // MARK: Layout-mode breakpoints
        /// At/above this width the full 3-column layout shows.
        static let regularBreakpoint: CGFloat = 1100
        /// At/above this width sidebar + grid can be visible.
        /// Below it, the grid gets priority and side panes auto-hide.
        static let mediumBreakpoint: CGFloat = 850
        /// Reference lower edge of the compact window range.
        static let compactBreakpoint: CGFloat = 760

        // MARK: Sidebar — fixed-ish, never grows to fill window
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarDefaultWidth: CGFloat = 230
        static let sidebarMin: CGFloat = sidebarMinWidth
        static let sidebarIdeal: CGFloat = sidebarDefaultWidth
        static let sidebarMax: CGFloat = 320

        // MARK: Inspector — fixed-ish, pinned right, never grows to fill window
        static let inspectorMin: CGFloat = 260
        static let inspectorDefaultWidth: CGFloat = 330
        static let inspectorIdeal: CGFloat = inspectorDefaultWidth
        static let inspectorMax: CGFloat = 440

        // MARK: Grid column (center) — the only flexible pane
        static let gridMinWidth: CGFloat = 520
        static let gridContentMin: CGFloat = 620
        static let gridContentIdeal: CGFloat = 800
        static let gridUsableMinRegular: CGFloat = gridMinWidth
        static let gridUsableMinMedium: CGFloat = gridMinWidth
        static let gridUsableMinCompact: CGFloat = 420

        // MARK: Split dividers
        static let splitDividerWidth: CGFloat = 8
        static let splitDividerVisibleWidth: CGFloat = 1

        // MARK: Inspector internals
        static let inspectorPadding: CGFloat = 22
        static let inspectorSectionSpacing: CGFloat = 26
        static let metadataLabelWidth: CGFloat = 86

        // MARK: Sidebar internals
        static let sidebarRowVPadding: CGFloat = 6
        static let sidebarRowHPadding: CGFloat = 10
        static let sidebarHorizontalInset: CGFloat = 6

        // MARK: Toolbar
        static let toolbarSearchMinWidth: CGFloat = 240
        static let toolbarSearchIdealWidth: CGFloat = 380
        static let toolbarSearchMaxWidth: CGFloat = 480

        // MARK: Filter bar
        static let filterBarHorizontalInset: CGFloat = 16
        static let filterBarVerticalInset: CGFloat = 8

        // MARK: Batch action bar
        /// Below this center-area width the batch bar drops button labels to
        /// short forms ("Tag" / "PDF") so the row still fits without clipping.
        static let batchBarCompactBreakpoint: CGFloat = 560
        static let batchBarHorizontalInset: CGFloat = 24
        static let batchBarBottomInset: CGFloat = 22

        /// `NSCollectionViewFlowLayout` tokens for the screenshot grid.
        enum Grid {
            // Card width band — `preferred` is the target; the layout snaps to
            // an integer column count and clamps the resulting per-card width
            // between `min` and `max`. Prevents tiny cards on narrow grids and
            // giant cards on wide grids. These are the *regular*-mode values;
            // `params(for:)` returns mode-specific overrides.
            static let minItemWidth: CGFloat = 200
            static let preferredItemWidth: CGFloat = 230
            static let maxItemWidth: CGFloat = 260

            /// Back-compat alias for callers that read a single "target".
            static let targetItemWidth: CGFloat = preferredItemWidth

            static let interitemSpacing: CGFloat = 24
            static let lineSpacing: CGFloat = 32
            static let sectionTop: CGFloat = 24
            static let sectionBottom: CGFloat = 28
            static let sectionHorizontal: CGFloat = 24

            static let cardThumbInset: CGFloat = 8
            static let cardLabelTopGap: CGFloat = 9
            static let cardLabelBottomGap: CGFloat = 2
            static let cardLabelHPadding: CGFloat = 10
            static let cardLabelBottomInset: CGFloat = 10
            static let thumbAspect: CGFloat = 0.72

            /// Mode-specific layout knobs the AppKit flow layout reads at
            /// `prepare()` time. Smaller modes use tighter spacing and a
            /// smaller card target so the grid still feels populated when the
            /// window is narrow. Cell-internal knobs (thumb aspect/inset, label
            /// gaps, fonts, checkmark) live here too so a single struct drives
            /// every visual change when the mode flips.
            struct ModeParams {
                // grid-layout level
                let target: CGFloat
                let minItem: CGFloat
                let maxItem: CGFloat
                let interitem: CGFloat
                let line: CGFloat
                let sectionH: CGFloat
                // cell-internal level
                let thumbAspect: CGFloat
                let thumbInset: CGFloat
                let labelTopGap: CGFloat
                let labelBottomGap: CGFloat
                let labelBottomInset: CGFloat
                let labelHPad: CGFloat
                let nameFontSize: CGFloat
                let nameLineHeight: CGFloat
                let dateFontSize: CGFloat
                let dateLineHeight: CGFloat
                let checkmarkSize: CGFloat
            }

            static func params(for mode: LayoutMode) -> ModeParams {
                params(for: mode, thumbnailSize: .medium)
            }

            static func params(for mode: LayoutMode, thumbnailSize: GridThumbnailSize) -> ModeParams {
                let base: ModeParams
                switch mode {
                case .regular:
                    base = ModeParams(
                        target: 230, minItem: 200, maxItem: 265,
                        interitem: 24, line: 32, sectionH: 24,
                        thumbAspect: 0.66, thumbInset: 8,
                        labelTopGap: 9, labelBottomGap: 2, labelBottomInset: 10, labelHPad: 10,
                        nameFontSize: 12, nameLineHeight: 16,
                        dateFontSize: 10.5, dateLineHeight: 14,
                        checkmarkSize: 18
                    )
                case .medium:
                    base = ModeParams(
                        target: 205, minItem: 190, maxItem: 240,
                        interitem: 20, line: 28, sectionH: 20,
                        thumbAspect: 0.64, thumbInset: 7,
                        labelTopGap: 8, labelBottomGap: 2, labelBottomInset: 9, labelHPad: 9,
                        nameFontSize: 11.5, nameLineHeight: 15,
                        dateFontSize: 10, dateLineHeight: 13,
                        checkmarkSize: 16
                    )
                case .compact:
                    base = ModeParams(
                        target: 170, minItem: 150, maxItem: 220,
                        interitem: 14, line: 22, sectionH: 14,
                        thumbAspect: 0.62, thumbInset: 6,
                        labelTopGap: 6, labelBottomGap: 1, labelBottomInset: 8, labelHPad: 8,
                        nameFontSize: 11, nameLineHeight: 14,
                        dateFontSize: 9.5, dateLineHeight: 12,
                        checkmarkSize: 14
                    )
                }
                let multiplier: CGFloat
                switch thumbnailSize {
                case .small: multiplier = 0.86
                case .medium: multiplier = 1.0
                case .large: multiplier = 1.16
                }
                return ModeParams(
                    target: base.target * multiplier,
                    minItem: base.minItem * multiplier,
                    maxItem: base.maxItem * multiplier,
                    interitem: base.interitem,
                    line: base.line,
                    sectionH: base.sectionH,
                    thumbAspect: base.thumbAspect,
                    thumbInset: base.thumbInset,
                    labelTopGap: base.labelTopGap,
                    labelBottomGap: base.labelBottomGap,
                    labelBottomInset: base.labelBottomInset,
                    labelHPad: base.labelHPad,
                    nameFontSize: base.nameFontSize,
                    nameLineHeight: base.nameLineHeight,
                    dateFontSize: base.dateFontSize,
                    dateLineHeight: base.dateLineHeight,
                    checkmarkSize: base.checkmarkSize
                )
            }
        }
    }

    /// Window-width-driven layout mode. Drives which split panes are visible
    /// and which grid item-size band the AppKit layout uses.
    enum LayoutMode: Equatable {
        /// ≥ regular breakpoint — full sidebar + grid + inspector.
        case regular
        /// ≥ medium breakpoint — sidebar + grid (inspector hidden).
        case medium
        /// < medium breakpoint — grid only.
        case compact

        static func from(width: CGFloat) -> LayoutMode {
            if width >= Theme.Layout.regularBreakpoint { return .regular }
            if width >= Theme.Layout.mediumBreakpoint  { return .medium }
            return .compact
        }
    }

    /// SwiftUI accent / selection palette. Backed by the system accent color
    /// so users who change tint in System Settings see it reflected.
    enum Palette {
        static var accent: Color { .accentColor }
        static var selectionFill: Color { .accentColor.opacity(0.14) }
        static var selectionStroke: Color { .accentColor.opacity(0.55) }
    }

    /// Semantic color wrappers that bridge to AppKit system colors so the
    /// app adapts to dark / light / increased-contrast modes.
    enum SemanticColor {
        static var panel: Color           { Color(nsColor: .controlBackgroundColor) }
        static var underPanel: Color      { Color(nsColor: .underPageBackgroundColor) }
        static var divider: Color         { Color(nsColor: .separatorColor) }
        static var label: Color           { Color(nsColor: .labelColor) }
        static var secondaryLabel: Color  { Color(nsColor: .secondaryLabelColor) }
        static var tertiaryLabel: Color   { Color(nsColor: .tertiaryLabelColor) }
        static var quaternary: Color      { Color(nsColor: .quaternaryLabelColor) }
        static var quietFill: Color       { Color(nsColor: .quaternaryLabelColor).opacity(0.5) }
    }
}

/// Small all-caps section header reused across the inspector.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Theme.SemanticColor.tertiaryLabel)
    }
}

/// Wrapping HStack used for tag pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth, x > 0 {
                w = max(w, x - spacing); x = 0; y += rowH + lineSpacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        w = max(w, x - spacing)
        return CGSize(width: w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + lineSpacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
