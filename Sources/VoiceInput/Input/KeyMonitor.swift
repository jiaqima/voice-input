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

    private static let holdThreshold: TimeInterval = 3.0

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

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
            print("Failed to create event tap. Accessibility permission required.")
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
        // Re-enable tap if disabled by system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)

        if fnPressed && fnDownTime == nil {
            // Fn key just pressed
            fnDownTime = Date()
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdThreshold, repeats: false) { [weak self] _ in
                guard let self = self, self.fnDownTime != nil else { return }
                self.isRecording = true
                self.onRecordingStart?()
            }
            // Suppress the event to prevent emoji picker
            return nil
        } else if !fnPressed && fnDownTime != nil {
            // Fn key released
            fnDownTime = nil
            holdTimer?.invalidate()
            holdTimer = nil

            if isRecording {
                isRecording = false
                onRecordingStop?()
                // Suppress release event
                return nil
            }

            // Short press: re-post the Fn key events so emoji picker etc. still work
            // We create a synthetic flagsChanged event with Fn flag
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
