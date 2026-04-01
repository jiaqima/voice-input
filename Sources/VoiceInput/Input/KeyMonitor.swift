import AppKit

final class KeyMonitor {
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private var monitor: Any?
    private var fnDownTime: Date?
    private var isRecording = false
    private var holdTimer: Timer?

    private static let holdThreshold: TimeInterval = 0.5

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        if monitor == nil {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Access Required"
                alert.informativeText = "Voice Input needs Accessibility access to monitor the Fn key. Please grant access in System Settings > Privacy & Security > Accessibility, then restart the app."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let fnActive = event.modifierFlags.contains(.function)

        if fnActive && fnDownTime == nil {
            fnDownTime = Date()
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdThreshold, repeats: false) { [weak self] _ in
                guard let self, self.fnDownTime != nil else { return }
                self.isRecording = true
                self.onRecordingStart?()
            }
        } else if !fnActive && fnDownTime != nil {
            fnDownTime = nil
            holdTimer?.invalidate()
            holdTimer = nil

            if isRecording {
                isRecording = false
                onRecordingStop?()
            }
        }
    }
}
