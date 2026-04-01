import AppKit
import Carbon

final class TextInjector {
    private let inputMethodManager = InputMethodManager()

    func inject(text: String) {
        // If CJK input method is active, temporarily switch to ASCII
        let needsSwitch = InputMethodManager.isCJKInputMethodActive()
        if needsSwitch {
            inputMethodManager.saveCurrentAndSwitchToASCII()
            usleep(50_000) // 50ms for input source switch
        }

        // Try direct Accessibility API insertion first (no clipboard needed)
        let inserted = insertViaAccessibility(text: text)

        if !inserted {
            // Fall back to clipboard paste
            NSLog("[TextInjector] AX insertion failed, falling back to clipboard paste")
            let pasteboard = NSPasteboard.general
            let savedItems = savePasteboard(pasteboard)

            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            simulatePaste()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.restorePasteboard(pasteboard, items: savedItems)
            }
        }

        // Restore input method after a delay
        if needsSwitch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.inputMethodManager.restorePreviousInputSource()
            }
        }
    }

    private func insertViaAccessibility(text: String) -> Bool {
        // Get the frontmost app's focused UI element
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("[TextInjector] No frontmost application")
            return false
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusResult == .success, let focused = focusedRef else {
            NSLog("[TextInjector] Could not get focused element from app (pid=%d): %d", frontApp.processIdentifier, focusResult.rawValue)
            return false
        }

        let element = focused as! AXUIElement

        // Log element role for debugging
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success {
            NSLog("[TextInjector] Focused element role: %@", roleRef as? String ?? "unknown")
        }

        // Check if the element supports setting selected text
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            NSLog("[TextInjector] Focused element does not support settable AXSelectedText")
            return false
        }

        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if result == .success {
            NSLog("[TextInjector] Successfully inserted text via AX")
            return true
        } else {
            NSLog("[TextInjector] AXUIElementSetAttributeValue failed: %d", result.rawValue)
            return false
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
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

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
