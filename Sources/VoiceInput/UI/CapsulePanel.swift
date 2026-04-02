import AppKit

final class CapsulePanel: NSPanel {
    private let minCapsuleHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let waveformWidth: CGFloat = 44
    private let minTextWidth: CGFloat = 160
    private let maxTextWidth: CGFloat = 560
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 12
    private let maxTextLines: Int = 3

    let waveformView = WaveformView()
    private let textLabel = NSTextField(labelWithString: "")
    private let backgroundView = NSVisualEffectView()
    private var currentTextWidth: CGFloat = 160
    private var dismissWorkItem: DispatchWorkItem?

    init() {
        let initialWidth = horizontalPadding + waveformWidth + 8 + minTextWidth + horizontalPadding
        let frame = NSRect(x: 0, y: 0, width: initialWidth, height: minCapsuleHeight)

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
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        setupViews()
    }

    private func setupViews() {
        guard let contentView = contentView else { return }

        // Background
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = cornerRadius
        backgroundView.layer?.masksToBounds = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView)

        // Waveform
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(waveformView)

        // Text label
        textLabel.font = .systemFont(ofSize: 15, weight: .medium)
        textLabel.textColor = .white
        textLabel.backgroundColor = .clear
        textLabel.isBordered = false
        textLabel.isEditable = false
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.maximumNumberOfLines = maxTextLines
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(textLabel)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            waveformView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: horizontalPadding),
            waveformView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: verticalPadding),
            waveformView.widthAnchor.constraint(equalToConstant: waveformWidth),
            waveformView.heightAnchor.constraint(equalToConstant: 32),

            textLabel.leadingAnchor.constraint(equalTo: waveformView.trailingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -horizontalPadding),
            textLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: verticalPadding),
            textLabel.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -verticalPadding),
        ])

        currentTextWidth = minTextWidth
    }

    func showRecording() {
        cancelDismissWorkItem()
        updateText("Listening...")
        positionAtBottom()

        alphaValue = 0
        setFrame(frame, display: true)

        // Entry spring animation
        let targetFrame = frame
        var startFrame = targetFrame
        startFrame.origin.y -= 20
        setFrame(startFrame, display: true)

        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = 1
            self.animator().setFrame(targetFrame, display: true)
        }

        waveformView.startAnimating()
    }

    func updateText(_ text: String) {
        let font = textLabel.font!
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        // Calculate desired width from single-line measurement
        let singleLineSize = (text as NSString).size(withAttributes: attributes)
        let desiredWidth = min(max(singleLineSize.width + 20, minTextWidth), maxTextWidth)
        let textAreaWidth = desiredWidth

        // Trim from front if text exceeds maxTextLines
        let displayText = trimmedToFit(text, font: font, width: textAreaWidth, maxLines: maxTextLines)
        textLabel.stringValue = displayText

        // Calculate multi-line text height
        let constrainRect = NSRect(x: 0, y: 0, width: textAreaWidth, height: .greatestFiniteMagnitude)
        let boundingRect = (displayText as NSString).boundingRect(
            with: constrainRect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let textHeight = ceil(boundingRect.height)
        let desiredHeight = max(minCapsuleHeight, textHeight + verticalPadding * 2)

        let totalWidth = horizontalPadding + waveformWidth + 8 + desiredWidth + horizontalPadding

        let widthChanged = abs(desiredWidth - currentTextWidth) > 10
        let heightChanged = abs(desiredHeight - frame.height) > 2

        if widthChanged || heightChanged {
            currentTextWidth = desiredWidth

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true

                var newFrame = self.frame
                let oldCenterX = newFrame.midX
                newFrame.size.width = totalWidth
                newFrame.size.height = desiredHeight
                newFrame.origin.x = oldCenterX - totalWidth / 2
                self.animator().setFrame(newFrame, display: true)
            }
            positionAtBottom()
        }
    }

    /// Trims text from the beginning so it fits within the given number of lines.
    private func trimmedToFit(_ text: String, font: NSFont, width: CGFloat, maxLines: Int) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let lineHeight = font.ascender - font.descender + font.leading
        let maxHeight = lineHeight * CGFloat(maxLines) + 4 // small tolerance

        let boundingRect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        if boundingRect.height <= maxHeight {
            return text
        }

        // Binary search for the longest suffix that fits
        var low = 0
        var high = text.count
        let chars = Array(text)

        while low < high {
            let mid = (low + high) / 2
            let candidate = "…" + String(chars[mid...])
            let rect = (candidate as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            if rect.height <= maxHeight {
                high = mid
            } else {
                low = mid + 1
            }
        }

        // Snap to word boundary if possible
        let trimIndex = low
        let suffix = String(chars[trimIndex...])
        if let spaceIndex = suffix.firstIndex(of: " ") {
            let wordAligned = "…" + String(suffix[suffix.index(after: spaceIndex)...])
            let rect = (wordAligned as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            if rect.height <= maxHeight {
                return wordAligned
            }
        }

        return "…" + suffix
    }

    func showRefining() {
        cancelDismissWorkItem()
        textLabel.stringValue = "Refining..."
        waveformView.stopAnimating()
    }

    func showStatus(_ text: String, dismissAfter delay: TimeInterval = 1.8) {
        cancelDismissWorkItem()
        waveformView.stopAnimating()
        updateText(text)
        positionAtBottom()
        alphaValue = 1
        orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func dismiss() {
        cancelDismissWorkItem()
        waveformView.stopAnimating()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = 0

            var f = self.frame
            f.origin.y -= 10
            f.size.width *= 0.95
            f.size.height *= 0.95
            f.origin.x += self.frame.width * 0.025
            self.animator().setFrame(f, display: true)
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
        })
    }

    private func cancelDismissWorkItem() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func positionAtBottom() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.origin.y + 60
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
