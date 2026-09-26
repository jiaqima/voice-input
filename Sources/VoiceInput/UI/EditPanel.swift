import AppKit

/// Floating, non-activating editor shown instead of injecting when the user
/// pressed Shift while dictating. Return inserts, Shift+Return adds a newline,
/// Escape discards.
final class EditPanel: NSPanel, NSTextViewDelegate {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let panelWidth: CGFloat = 560
    private let minTextHeight: CGFloat = 24
    private let maxTextHeight: CGFloat = 220
    private let cornerRadius: CGFloat = 20
    private let horizontalPadding: CGFloat = 18
    private let verticalPadding: CGFloat = 12
    private let hintHeight: CGFloat = 16

    private let backgroundView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let hintLabel = NSTextField(labelWithString: "↩ insert    ⇧↩ newline    esc discard")
    private var textHeightConstraint: NSLayoutConstraint!

    override var canBecomeKey: Bool { true }

    init() {
        let frame = NSRect(x: 0, y: 0, width: panelWidth, height: 80)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        setupViews()
    }

    private func setupViews() {
        guard let contentView = contentView else { return }

        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = cornerRadius
        backgroundView.layer?.masksToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView)

        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textView.font = font
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: minTextHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(scrollView)

        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        hintLabel.backgroundColor = .clear
        hintLabel.isBordered = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(hintLabel)

        textHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: minTextHeight)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: horizontalPadding),
            scrollView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -horizontalPadding),
            scrollView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: verticalPadding),
            textHeightConstraint,

            hintLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            hintLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            hintLabel.heightAnchor.constraint(equalToConstant: hintHeight),
            hintLabel.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -verticalPadding),
        ])
    }

    // MARK: - Presentation

    func present(text: String) {
        textView.string = text
        textView.undoManager?.removeAllActions()
        resizeToFit()
        positionAtBottom()
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    func dismissEditor() {
        guard isVisible else { return }
        orderOut(nil)
    }

    private func resizeToFit() {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let contentWidth = panelWidth - horizontalPadding * 2
        container.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = ceil(layoutManager.usedRect(for: container).height) + textView.textContainerInset.height * 2
        let textHeight = min(max(used, minTextHeight), maxTextHeight)
        textHeightConstraint.constant = textHeight

        let totalHeight = verticalPadding + textHeight + 6 + hintHeight + verticalPadding
        var f = frame
        f.size = NSSize(width: panelWidth, height: totalHeight)
        setFrame(f, display: true)
    }

    private func positionAtBottom() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.origin.y + 60
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Actions

    private func commit() {
        let text = textView.string
        dismissEditor()
        onCommit?(text)
    }

    private func cancel() {
        dismissEditor()
        onCancel?()
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                commit()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) {
        resizeToFit()
        positionAtBottom()
    }
}
