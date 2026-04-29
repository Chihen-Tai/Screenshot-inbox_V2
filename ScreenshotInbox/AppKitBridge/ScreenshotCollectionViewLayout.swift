import AppKit

/// Adaptive flow layout for the screenshot grid. Reads spacing/insets from
/// `Theme.Layout.Grid` for the initial regular-mode defaults, then accepts
/// mode-specific overrides via `apply(params:)`. Resizes items so the
/// thumbnail aspect and label rhythm stay consistent across column counts.
final class ScreenshotCollectionViewLayout: NSCollectionViewFlowLayout {
    var targetItemWidth: CGFloat = Theme.Layout.Grid.targetItemWidth
    private var lastDebugSummary: String = ""
    private var currentMinItem: CGFloat = Theme.Layout.Grid.minItemWidth
    private var currentMaxItem: CGFloat = Theme.Layout.Grid.maxItemWidth
    private var currentThumbAspect: CGFloat = Theme.Layout.Grid.thumbAspect
    private var currentThumbInset: CGFloat = Theme.Layout.Grid.cardThumbInset
    private var currentLabelTopGap: CGFloat = Theme.Layout.Grid.cardLabelTopGap
    private var currentLabelBottomGap: CGFloat = Theme.Layout.Grid.cardLabelBottomGap
    private var currentLabelBottomInset: CGFloat = Theme.Layout.Grid.cardLabelBottomInset
    private var currentNameLineHeight: CGFloat = 16
    private var currentDateLineHeight: CGFloat = 14

    /// Push mode-specific spacing/sizing into the layout. The controller calls
    /// this whenever the SwiftUI side reports a new `LayoutMode`. Vertical
    /// section insets stay on the regular-mode defaults — only horizontal
    /// rhythm responds to mode, which keeps the top/bottom breathing room
    /// consistent.
    func apply(params: Theme.Layout.Grid.ModeParams) {
        targetItemWidth = params.target
        currentMinItem = params.minItem
        currentMaxItem = params.maxItem
        currentThumbAspect = params.thumbAspect
        currentThumbInset = params.thumbInset
        currentLabelTopGap = params.labelTopGap
        currentLabelBottomGap = params.labelBottomGap
        currentLabelBottomInset = params.labelBottomInset
        currentNameLineHeight = params.nameLineHeight
        currentDateLineHeight = params.dateLineHeight
        minimumInteritemSpacing = params.interitem
        minimumLineSpacing = params.line
        sectionInset = NSEdgeInsets(
            top: Theme.Layout.Grid.sectionTop,
            left: params.sectionH,
            bottom: Theme.Layout.Grid.sectionBottom,
            right: params.sectionH
        )
        invalidateLayout()
    }

    override init() {
        super.init()
        self.scrollDirection = .vertical
        self.minimumInteritemSpacing = Theme.Layout.Grid.interitemSpacing
        self.minimumLineSpacing = Theme.Layout.Grid.lineSpacing
        self.sectionInset = NSEdgeInsets(
            top: Theme.Layout.Grid.sectionTop,
            left: Theme.Layout.Grid.sectionHorizontal,
            bottom: Theme.Layout.Grid.sectionBottom,
            right: Theme.Layout.Grid.sectionHorizontal
        )
        self.itemSize = NSSize(width: targetItemWidth, height: 220)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func prepare() {
        if let cv = collectionView {
            let avail = cv.bounds.width - sectionInset.left - sectionInset.right
            if avail > 0 {
                let gap = minimumInteritemSpacing
                let minW = currentMinItem
                let maxW = currentMaxItem

                // Pick a column count so the resulting per-card width sits in
                // the [min, max] band and stays close to the preferred target.
                // For width avail and N columns: w(N) = (avail - (N-1)·gap) / N
                // - nMaxByMin = densest legal layout (smallest cards still ≥ min)
                // - nMinByMax = sparsest legal layout (biggest cards still ≤ max)
                let nMaxByMin = max(1, floor((avail + gap) / (minW + gap)))
                let nMinByMax = max(1, ceil((avail + gap) / (maxW + gap)))
                let nPreferred = max(1, floor((avail + gap) / (targetItemWidth + gap)))

                // Cap at nMaxByMin so cards never overflow the available width.
                // When the band degenerates (window narrower than minW), fall
                // back to the densest legal value — which will be 1.
                let cols: CGFloat
                if nMinByMax > nMaxByMin {
                    cols = nMaxByMin
                } else {
                    cols = max(nMinByMax, min(nMaxByMin, nPreferred))
                }

                let raw = (avail - (cols - 1) * gap) / cols
                // Single-column very-narrow case: drop the min floor so the
                // lone card can shrink to fit the window instead of clipping.
                let w: CGFloat
                if cols == 1 && raw < minW {
                    w = floor(min(maxW, max(0, avail)))
                } else {
                    w = floor(min(maxW, max(minW, raw)))
                }

                let thumbW = w - 2 * currentThumbInset
                let thumbH = thumbW * currentThumbAspect
                let labelsBlock: CGFloat =
                    currentLabelTopGap
                    + currentNameLineHeight
                    + currentLabelBottomGap
                    + currentDateLineHeight
                    + currentLabelBottomInset
                let h = thumbH + 2 * currentThumbInset + labelsBlock
                self.itemSize = NSSize(width: w, height: h)
                #if DEBUG
                let summary = "bounds=\(Int(cv.bounds.width)) avail=\(Int(avail)) columns=\(Int(cols)) item=\(Int(w))x\(Int(h))"
                if summary != lastDebugSummary {
                    print("[GridLayout] \(summary)")
                    lastDebugSummary = summary
                }
                #endif
            }
        }
        super.prepare()
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        let currentWidth = collectionView?.bounds.width ?? 0
        if abs(currentWidth - newBounds.width) > 0.5 { return true }
        return super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
}
