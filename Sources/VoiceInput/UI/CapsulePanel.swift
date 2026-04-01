import AppKit

final class CapsulePanel: NSPanel {
    private let capsuleHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let waveformWidth: CGFloat = 44
    private let minTextWidth: CGFloat = 160
    private let maxTextWidth: CGFloat = 560
    private let horizontalPadding: CGFloat = 20

    let waveformView = WaveformView()
    private let textLabel = NSTextField(labelWithString: "")
    private let backgroundView = NSVisualEffectView()
    private var currentTextWidth: CGFloat = 160

    init() {
        let initialWidth = horizontalPadding + waveformWidth + 8 + minTextWidth + horizontalPadding
        let frame = NSRect(x: 0, y: 0, width: initialWidth, height: capsuleHeight)

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
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(textLabel)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            waveformView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: horizontalPadding),
            waveformView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: waveformWidth),
            waveformView.heightAnchor.constraint(equalToConstant: 32),

            textLabel.leadingAnchor.constraint(equalTo: waveformView.trailingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -horizontalPadding),
            textLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
        ])

        currentTextWidth = minTextWidth
    }

    func showRecording() {
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
        textLabel.stringValue = text

        // Calculate desired text width
        let attributes: [NSAttributedString.Key: Any] = [.font: textLabel.font!]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let desiredWidth = min(max(textSize.width + 20, minTextWidth), maxTextWidth)

        if abs(desiredWidth - currentTextWidth) > 10 {
            currentTextWidth = desiredWidth
            let totalWidth = horizontalPadding + waveformWidth + 8 + currentTextWidth + horizontalPadding

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true

                var newFrame = self.frame
                let oldCenterX = newFrame.midX
                newFrame.size.width = totalWidth
                newFrame.origin.x = oldCenterX - totalWidth / 2
                self.animator().setFrame(newFrame, display: true)
            }
        }
    }

    func showRefining() {
        textLabel.stringValue = "Refining..."
        waveformView.stopAnimating()
    }

    func dismiss() {
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

    private func positionAtBottom() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.origin.y + 60
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
