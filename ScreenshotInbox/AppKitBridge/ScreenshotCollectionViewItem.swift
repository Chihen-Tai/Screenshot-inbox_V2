import AppKit
import SwiftUI

/// Single grid cell. Hosts `MockThumbnailView` (SwiftUI) inside an
/// `NSHostingView` and pairs it with two `NSTextField` labels.
///
/// Visual states:
/// - default: subtle thumbnail container, no card border
/// - hovering: faint card tint + slightly stronger thumbnail container
/// - selected: soft accent tint behind card + accent ring around thumbnail
///   + small checkmark badge
final class ScreenshotCollectionViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ScreenshotCollectionViewItem")

    private let backgroundView = NSView()
    private let thumbnailContainer = NSView()
    private let nameField = NSTextField(labelWithString: "")
    private let dateField = NSTextField(labelWithString: "")
    private let checkmarkView = NSImageView()
    private var thumbnailHost: NSHostingView<MockThumbnailView>!
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    // Mutable constraints driven by the active LayoutMode. The aspect-ratio
    // constraint uses an immutable `multiplier`, so swapping modes means
    // deactivating + rebuilding it; the rest just need their `constant`
    // updated.
    private var thumbAspectConstraint: NSLayoutConstraint!
    private var thumbLeadingConstraint: NSLayoutConstraint!
    private var thumbTrailingConstraint: NSLayoutConstraint!
    private var thumbTopConstraint: NSLayoutConstraint!
    private var nameLeadingConstraint: NSLayoutConstraint!
    private var nameTrailingConstraint: NSLayoutConstraint!
    private var nameTopConstraint: NSLayoutConstraint!
    private var dateLeadingConstraint: NSLayoutConstraint!
    private var dateTrailingConstraint: NSLayoutConstraint!
    private var dateTopConstraint: NSLayoutConstraint!
    private var dateBottomConstraint: NSLayoutConstraint!
    private var checkmarkWidthConstraint: NSLayoutConstraint!
    private var checkmarkHeightConstraint: NSLayoutConstraint!

    private var currentParams: Theme.Layout.Grid.ModeParams =
        Theme.Layout.Grid.params(for: .regular)

    /// Click callback that carries modifier flags so the controller can
    /// dispatch single / Cmd / Shift selection without going through
    /// NSCollectionView's modifier-blind delegate.
    var onClick: ((NSEvent.ModifierFlags) -> Void)?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        view = root

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = Theme.Radius.card
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backgroundView)

        thumbnailContainer.wantsLayer = true
        thumbnailContainer.layer?.cornerRadius = Theme.Radius.thumb
        thumbnailContainer.layer?.masksToBounds = true
        thumbnailContainer.layer?.borderWidth = 0
        thumbnailContainer.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(thumbnailContainer)

        thumbnailHost = NSHostingView(rootView: MockThumbnailView(kind: .document))
        thumbnailHost.translatesAutoresizingMaskIntoConstraints = false
        thumbnailContainer.addSubview(thumbnailHost)

        nameField.font = .systemFont(ofSize: currentParams.nameFontSize, weight: .medium)
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.maximumNumberOfLines = 1
        nameField.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(nameField)

        dateField.font = .systemFont(ofSize: currentParams.dateFontSize)
        dateField.textColor = .secondaryLabelColor
        dateField.lineBreakMode = .byTruncatingTail
        dateField.maximumNumberOfLines = 1
        dateField.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(dateField)

        configureCheckmark()
        backgroundView.addSubview(checkmarkView)

        let p = currentParams

        thumbLeadingConstraint = thumbnailContainer.leadingAnchor.constraint(
            equalTo: backgroundView.leadingAnchor, constant: p.thumbInset)
        thumbTrailingConstraint = thumbnailContainer.trailingAnchor.constraint(
            equalTo: backgroundView.trailingAnchor, constant: -p.thumbInset)
        thumbTopConstraint = thumbnailContainer.topAnchor.constraint(
            equalTo: backgroundView.topAnchor, constant: p.thumbInset)
        thumbAspectConstraint = thumbnailContainer.heightAnchor.constraint(
            equalTo: thumbnailContainer.widthAnchor, multiplier: p.thumbAspect)

        nameLeadingConstraint = nameField.leadingAnchor.constraint(
            equalTo: backgroundView.leadingAnchor, constant: p.labelHPad)
        nameTrailingConstraint = nameField.trailingAnchor.constraint(
            equalTo: backgroundView.trailingAnchor, constant: -p.labelHPad)
        nameTopConstraint = nameField.topAnchor.constraint(
            equalTo: thumbnailContainer.bottomAnchor, constant: p.labelTopGap)

        dateLeadingConstraint = dateField.leadingAnchor.constraint(
            equalTo: backgroundView.leadingAnchor, constant: p.labelHPad)
        dateTrailingConstraint = dateField.trailingAnchor.constraint(
            equalTo: backgroundView.trailingAnchor, constant: -p.labelHPad)
        dateTopConstraint = dateField.topAnchor.constraint(
            equalTo: nameField.bottomAnchor, constant: p.labelBottomGap)
        dateBottomConstraint = dateField.bottomAnchor.constraint(
            lessThanOrEqualTo: backgroundView.bottomAnchor, constant: -p.labelBottomInset)

        checkmarkWidthConstraint = checkmarkView.widthAnchor.constraint(equalToConstant: p.checkmarkSize)
        checkmarkHeightConstraint = checkmarkView.heightAnchor.constraint(equalToConstant: p.checkmarkSize)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: root.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            thumbLeadingConstraint,
            thumbTrailingConstraint,
            thumbTopConstraint,
            thumbAspectConstraint,

            thumbnailHost.leadingAnchor.constraint(equalTo: thumbnailContainer.leadingAnchor),
            thumbnailHost.trailingAnchor.constraint(equalTo: thumbnailContainer.trailingAnchor),
            thumbnailHost.topAnchor.constraint(equalTo: thumbnailContainer.topAnchor),
            thumbnailHost.bottomAnchor.constraint(equalTo: thumbnailContainer.bottomAnchor),

            nameLeadingConstraint,
            nameTrailingConstraint,
            nameTopConstraint,

            dateLeadingConstraint,
            dateTrailingConstraint,
            dateTopConstraint,
            dateBottomConstraint,

            checkmarkView.topAnchor.constraint(equalTo: thumbnailContainer.topAnchor, constant: 6),
            checkmarkView.trailingAnchor.constraint(equalTo: thumbnailContainer.trailingAnchor, constant: -6),
            checkmarkWidthConstraint,
            checkmarkHeightConstraint,
        ])

        applyAppearance()
    }

    /// Push the active layout-mode params into the cell. Updates label fonts,
    /// checkmark size, thumb inset/aspect, and label gaps. The aspect-ratio
    /// constraint's `multiplier` is immutable, so we deactivate + replace it
    /// when the mode flips.
    func applyParams(_ params: Theme.Layout.Grid.ModeParams) {
        guard isViewLoaded else {
            currentParams = params
            return
        }
        let aspectChanged = abs(params.thumbAspect - currentParams.thumbAspect) > 0.0001
        currentParams = params

        nameField.font = .systemFont(ofSize: params.nameFontSize, weight: .medium)
        dateField.font = .systemFont(ofSize: params.dateFontSize)

        thumbLeadingConstraint.constant = params.thumbInset
        thumbTrailingConstraint.constant = -params.thumbInset
        thumbTopConstraint.constant = params.thumbInset

        nameLeadingConstraint.constant = params.labelHPad
        nameTrailingConstraint.constant = -params.labelHPad
        nameTopConstraint.constant = params.labelTopGap

        dateLeadingConstraint.constant = params.labelHPad
        dateTrailingConstraint.constant = -params.labelHPad
        dateTopConstraint.constant = params.labelBottomGap
        dateBottomConstraint.constant = -params.labelBottomInset

        checkmarkWidthConstraint.constant = params.checkmarkSize
        checkmarkHeightConstraint.constant = params.checkmarkSize
        configureCheckmark(pointSize: params.checkmarkSize)

        if aspectChanged {
            thumbAspectConstraint.isActive = false
            thumbAspectConstraint = thumbnailContainer.heightAnchor.constraint(
                equalTo: thumbnailContainer.widthAnchor, multiplier: params.thumbAspect)
            thumbAspectConstraint.isActive = true
        }

        view.needsLayout = true
    }

    private func configureCheckmark(pointSize: CGFloat = 16) {
        let base = NSImage(systemSymbolName: "checkmark.circle.fill",
                           accessibilityDescription: "Selected")
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .controlAccentColor]))
        checkmarkView.image = base?.withSymbolConfiguration(cfg)
        checkmarkView.imageScaling = .scaleProportionallyUpOrDown
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.isHidden = true
        checkmarkView.wantsLayer = true
        checkmarkView.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.20)
            s.shadowOffset = NSSize(width: 0, height: -1)
            s.shadowBlurRadius = 2
            return s
        }()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        installTrackingArea()
    }

    private func installTrackingArea() {
        if let existing = trackingArea { view.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    func configure(with screenshot: Screenshot) {
        thumbnailHost.rootView = MockThumbnailView(kind: screenshot.thumbnailKind)
        nameField.stringValue = screenshot.name
        dateField.stringValue = Self.dateFormatter.string(from: screenshot.createdAt)
    }

    override var isSelected: Bool {
        didSet { applyAppearance() }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovering = false
        onClick = nil
        applyAppearance()
    }

    /// Take over click handling: forward modifier flags up and suppress the
    /// default NSCollectionView behavior so the controller is the single
    /// source of truth for selection.
    override func mouseDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        onClick?(mods)
    }

    private func applyAppearance() {
        let cardBG: NSColor
        if isSelected {
            cardBG = NSColor.controlAccentColor.withAlphaComponent(0.12)
        } else if isHovering {
            cardBG = NSColor.labelColor.withAlphaComponent(0.045)
        } else {
            cardBG = .clear
        }
        backgroundView.layer?.backgroundColor = cardBG.cgColor

        let containerBG = NSColor.labelColor.withAlphaComponent(isHovering ? 0.06 : 0.04)
        thumbnailContainer.layer?.backgroundColor = containerBG.cgColor

        if isSelected {
            thumbnailContainer.layer?.borderWidth = 1.0
            thumbnailContainer.layer?.borderColor = NSColor.controlAccentColor
                .withAlphaComponent(0.55).cgColor
        } else {
            thumbnailContainer.layer?.borderWidth = 0
            thumbnailContainer.layer?.borderColor = nil
        }

        checkmarkView.isHidden = !isSelected
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
