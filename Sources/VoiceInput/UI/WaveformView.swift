import AppKit

final class WaveformView: NSView {
    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let barCount = 5
    private let barWidth: CGFloat = 4.0
    private let barSpacing: CGFloat = 3.5
    private let minBarHeight: CGFloat = 6.0
    private let maxBarHeight: CGFloat = 28.0

    private let attackRate: CGFloat = 0.40
    private let releaseRate: CGFloat = 0.15

    private var smoothedLevel: CGFloat = 0
    private var barLevels: [CGFloat] = [0, 0, 0, 0, 0]
    private var displayLink: CVDisplayLink?
    private var rawLevel: CGFloat = 0

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func startAnimating() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link = link else { return }

        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<WaveformView>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                view.updateAnimation()
            }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        CVDisplayLinkStart(link)
        displayLink = link
    }

    func stopAnimating() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
        smoothedLevel = 0
        barLevels = [0, 0, 0, 0, 0]
        needsDisplay = true
    }

    func setLevel(_ level: Float) {
        rawLevel = CGFloat(level)
    }

    private func updateAnimation() {
        let target = rawLevel

        // Envelope follower
        if target > smoothedLevel {
            smoothedLevel += (target - smoothedLevel) * attackRate
        } else {
            smoothedLevel += (target - smoothedLevel) * releaseRate
        }

        // Update per-bar levels with jitter
        for i in 0..<barCount {
            let jitter = CGFloat.random(in: -0.04...0.04)
            let weighted = smoothedLevel * barWeights[i] + jitter
            barLevels[i] = max(0, min(1, weighted))
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.height / 2

        context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)

        for i in 0..<barCount {
            let barHeight = minBarHeight + barLevels[i] * (maxBarHeight - minBarHeight)
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = centerY - barHeight / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            path.fill()
        }
    }
}
