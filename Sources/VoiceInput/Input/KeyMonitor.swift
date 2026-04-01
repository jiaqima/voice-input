import AppKit
import CoreGraphics

final class KeyMonitor {
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnDownTime: Date?
    private var isRecording = false
    private var holdTimer: Timer?

    private static let holdThreshold: TimeInterval = 0.5
    // keycode 63 = kVK_Function (Globe/Fn key on modern Macs)
    private static let fnKeyCode: Int64 = 63

    func start() {
        // Listen for flagsChanged (older Macs) AND keyDown/keyUp (newer Globe key Macs)
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Access Required"
                alert.informativeText = "Voice Input needs Accessibility access to monitor the Fn key. Please grant access in System Settings > Privacy & Security > Accessibility, then restart the app."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        holdTimer?.invalidate()
        holdTimer = nil
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        let isFnPress: Bool
        let isFnRelease: Bool

        switch type {
        case .flagsChanged:
            let fnActive = event.flags.contains(.maskSecondaryFn)
            isFnPress   = fnActive && fnDownTime == nil
            isFnRelease = !fnActive && fnDownTime != nil

        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Self.fnKeyCode,
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                return Unmanaged.passRetained(event)
            }
            isFnPress   = fnDownTime == nil
            isFnRelease = false

        case .keyUp:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Self.fnKeyCode else {
                return Unmanaged.passRetained(event)
            }
            isFnPress   = false
            isFnRelease = fnDownTime != nil

        default:
            return Unmanaged.passRetained(event)
        }

        if isFnPress {
            fnDownTime = Date()
            holdTimer?.invalidate()
            // The run loop source is on the main run loop, so this callback runs on the
            // main thread — Timer.scheduledTimer is safe here without DispatchQueue.main.async.
            holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdThreshold, repeats: false) { [weak self] _ in
                guard let self = self, self.fnDownTime != nil else { return }
                self.isRecording = true
                self.onRecordingStart?()
            }
            return nil  // suppress to prevent emoji picker on hold
        }

        if isFnRelease {
            let wasRecording = isRecording
            fnDownTime = nil
            holdTimer?.invalidate()
            holdTimer = nil

            if wasRecording {
                isRecording = false
                onRecordingStop?()
                return nil
            }

            // Short press: re-post synthetic events so emoji picker still works
            if let fnDown = CGEvent(source: nil) {
                fnDown.type = .flagsChanged
                fnDown.flags = [.maskSecondaryFn]
                fnDown.post(tap: .cgSessionEventTap)
            }
            if let fnUp = CGEvent(source: nil) {
                fnUp.type = .flagsChanged
                fnUp.flags = []
                fnUp.post(tap: .cgSessionEventTap)
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
