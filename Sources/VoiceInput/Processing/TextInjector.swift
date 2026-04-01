import AppKit
import Carbon

final class TextInjector {
    enum PasteStrategy: String {
        case applescript
        case hid
        case session
        case pid
    }

    enum InjectionResult {
        case accessibilitySuccess
        case typingSimulationSuccess
        case automaticPastePosted(PasteStrategy)
        case manualPasteRequired
    }

    struct TargetContext {
        let processIdentifier: pid_t
        let localizedName: String?
        let bundleIdentifier: String?
    }

    private struct FocusedElementContext {
        let target: TargetContext
        let element: AXUIElement
        let role: String
    }

    private let inputMethodManager = InputMethodManager()

    func captureTargetContext() -> TargetContext? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return TargetContext(
            processIdentifier: frontApp.processIdentifier,
            localizedName: frontApp.localizedName,
            bundleIdentifier: frontApp.bundleIdentifier
        )
    }

    func inject(
        text: String,
        targetContext: TargetContext?,
        completion: @escaping (InjectionResult) -> Void
    ) {
        let resolvedTarget = targetContext ?? captureTargetContext()
        logTargetContext(resolvedTarget)

        // If CJK input method is active, temporarily switch to ASCII
        let needsSwitch = InputMethodManager.isCJKInputMethodActive()
        if needsSwitch {
            inputMethodManager.saveCurrentAndSwitchToASCII()
            usleep(50_000) // 50ms for input source switch
        }

        let result: InjectionResult
        if simulateTyping(text: text) {
            result = .typingSimulationSuccess
        } else if insertViaAccessibility(text: text, preferredTarget: resolvedTarget) {
            result = .accessibilitySuccess
        } else {
            result = fallBackToClipboardPaste(text: text, targetContext: resolvedTarget)
        }

        // Restore input method after a delay so pasted/manual text stays ASCII-safe.
        let restoreInputMethod = { [weak self] in
            if needsSwitch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.inputMethodManager.restorePreviousInputSource()
                }
            }
        }

        restoreInputMethod()
        completion(result)
    }

    private func logTargetContext(_ targetContext: TargetContext?) {
        guard let targetContext else {
            NSLog("[TextInjector] No captured target app; injection will use live context/fallbacks")
            return
        }

        NSLog(
            "[TextInjector] Target app: %@ (pid=%d bundle=%@)",
            targetContext.localizedName ?? "unknown",
            targetContext.processIdentifier,
            targetContext.bundleIdentifier ?? "unknown"
        )
    }

    private func liveFrontmostTargetContext() -> TargetContext? {
        captureTargetContext()
    }

    private func focusedElementContext(for targetContext: TargetContext?) -> FocusedElementContext? {
        guard let targetContext else {
            NSLog("[TextInjector] No target context available for AX insertion")
            return nil
        }

        let appElement = AXUIElementCreateApplication(targetContext.processIdentifier)
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard focusResult == .success, let focusedRef else {
            NSLog(
                "[TextInjector] Could not get focused element from %@ (pid=%d): %d",
                targetContext.localizedName ?? "unknown",
                targetContext.processIdentifier,
                focusResult.rawValue
            )
            return nil
        }

        let element = focusedRef as! AXUIElement
        let role = stringValue(of: kAXRoleAttribute as CFString, for: element) ?? "unknown"
        NSLog("[TextInjector] Focused element role: %@", role)

        return FocusedElementContext(target: targetContext, element: element, role: role)
    }

    private func insertViaAccessibility(text: String, preferredTarget: TargetContext?) -> Bool {
        if let preferredTarget,
           let context = focusedElementContext(for: preferredTarget),
           insertViaAccessibility(text: text, context: context) {
            NSLog("[TextInjector] AX insertion succeeded on captured target app")
            return true
        }

        let liveTarget = liveFrontmostTargetContext()
        if let liveTarget,
           liveTarget.processIdentifier != preferredTarget?.processIdentifier {
            NSLog(
                "[TextInjector] Retrying AX insertion against live frontmost app: %@ (pid=%d bundle=%@)",
                liveTarget.localizedName ?? "unknown",
                liveTarget.processIdentifier,
                liveTarget.bundleIdentifier ?? "unknown"
            )
        }

        if let liveTarget,
           let context = focusedElementContext(for: liveTarget),
           insertViaAccessibility(text: text, context: context) {
            NSLog("[TextInjector] AX insertion succeeded on live frontmost app")
            return true
        }

        NSLog("[TextInjector] AX insertion failed on both captured and live targets")
        return false
    }

    private func insertViaAccessibility(text: String, context: FocusedElementContext) -> Bool {
        NSLog("[TextInjector] Trying AXSelectedText insertion for role %@", context.role)

        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            context.element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )

        guard settableResult == .success, settable.boolValue else {
            NSLog("[TextInjector] Focused element does not support settable AXSelectedText")
            return false
        }

        let result = AXUIElementSetAttributeValue(
            context.element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if result == .success {
            NSLog("[TextInjector] Successfully inserted text via AXSelectedText")
            return true
        }

        NSLog("[TextInjector] AXSelectedText insertion failed: %d", result.rawValue)
        return false
    }

    /// Simulate typing by injecting Unicode text via CGEvent, the same mechanism macOS Dictation uses.
    private func simulateTyping(text: String) -> Bool {
        NSLog("[TextInjector] Trying CGEvent typing simulation (%d characters)", text.count)

        let source = CGEventSource(stateID: .hidSystemState)

        // CGEventKeyboardSetUnicodeString accepts up to ~20 UTF-16 code units per event.
        // We chunk the text and send each chunk as a key-down/key-up pair.
        let utf16 = Array(text.utf16)
        let chunkSize = 20
        for offset in stride(from: 0, to: utf16.count, by: chunkSize) {
            let end = min(offset + chunkSize, utf16.count)
            var chunk = Array(utf16[offset..<end])

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                NSLog("[TextInjector] Failed to create CGEvent for typing simulation")
                return false
            }

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: 0, unicodeString: &chunk)

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }

        NSLog("[TextInjector] Typing simulation completed")
        return true
    }

    private func stringValue(of attribute: CFString, for element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success else { return nil }
        return valueRef as? String
    }

    private func fallBackToClipboardPaste(text: String, targetContext: TargetContext?) -> InjectionResult {
        NSLog("[TextInjector] Falling back to clipboard paste")

        let pasteboard = NSPasteboard.general
        let previousItems = savePasteboard(pasteboard)
        NSLog("[TextInjector] Saved %d pasteboard item(s) before fallback", previousItems.count)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Brief pause so the target app recognises the clipboard change
        usleep(50_000)

        if let strategy = simulatePaste(targetContext: targetContext) {
            NSLog(
                "[TextInjector] Automatic paste posted via %@",
                strategy.rawValue
            )
            // Restore the previous clipboard contents after the paste has time to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !previousItems.isEmpty {
                    pasteboard.clearContents()
                    pasteboard.writeObjects(previousItems)
                    NSLog("[TextInjector] Restored %d pasteboard item(s) after paste", previousItems.count)
                }
            }
            return .automaticPastePosted(strategy)
        }

        NSLog("[TextInjector] No automatic paste strategy could be posted; transcript left on clipboard")
        return .manualPasteRequired
    }

    private func simulatePaste(targetContext: TargetContext?) -> PasteStrategy? {
        let strategies = pasteStrategies(for: targetContext)
        for strategy in strategies {
            NSLog("[TextInjector] Trying paste strategy %@ for %@", strategy.rawValue, targetContext?.bundleIdentifier ?? "unknown app")
            switch strategy {
            case .applescript:
                if simulatePasteViaAppleScript() {
                    return .applescript
                }

            case .hid, .session, .pid:
                if let result = simulatePasteViaCGEvent(strategy: strategy, targetContext: targetContext) {
                    return result
                }
            }
        }

        return nil
    }

    private func simulatePasteViaAppleScript() -> Bool {
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            NSLog("[TextInjector] AppleScript paste failed: %@", error.description)
            return false
        }
        return true
    }

    private func simulatePasteViaCGEvent(strategy: PasteStrategy, targetContext: TargetContext?) -> PasteStrategy? {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let source else {
            NSLog("[TextInjector] Failed to create CGEventSource for paste fallback")
            return nil
        }

        let commandKeyCode: CGKeyCode = 55
        let vKeyCode: CGKeyCode = 9
        guard let events = makePasteEvents(source: source, commandKeyCode: commandKeyCode, vKeyCode: vKeyCode) else {
            NSLog("[TextInjector] Failed to create CGEvents for paste fallback")
            return nil
        }

        switch strategy {
        case .hid:
            events.forEach { $0.post(tap: .cghidEventTap) }
            return .hid
        case .session:
            events.forEach { $0.post(tap: .cgSessionEventTap) }
            return .session
        case .pid:
            guard let targetContext else { return nil }
            events.forEach { $0.postToPid(targetContext.processIdentifier) }
            return .pid
        case .applescript:
            return nil // handled separately
        }
    }

    private func pasteStrategies(for targetContext: TargetContext?) -> [PasteStrategy] {
        // AppleScript via System Events is the most reliable across app types (including Electron).
        // CGEvent strategies are kept as fallbacks.
        return [.applescript, .hid]
    }

    private func makePasteEvents(
        source: CGEventSource,
        commandKeyCode: CGKeyCode,
        vKeyCode: CGKeyCode
    ) -> [CGEvent]? {
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false) else {
            return nil
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []

        return [commandDown, vDown, vUp, commandUp]
    }

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        var saved: [NSPasteboardItem] = []
        guard let items = pasteboard.pasteboardItems else { return saved }

        for item in items {
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            saved.append(newItem)
        }
        return saved
    }
}
