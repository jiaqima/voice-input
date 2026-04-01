import AppKit
import Carbon

final class TextInjector {
    private let inputMethodManager = InputMethodManager()

    func inject(text: String) {
        let pasteboard = NSPasteboard.general
        // Save current clipboard
        let savedItems = savePasteboard(pasteboard)

        // Write text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // If CJK input method is active, temporarily switch to ASCII
        let needsSwitch = InputMethodManager.isCJKInputMethodActive()
        if needsSwitch {
            inputMethodManager.saveCurrentAndSwitchToASCII()
            // Small delay to let the input source switch take effect
            usleep(50_000) // 50ms
        }

        // Simulate Cmd+V
        simulatePaste()

        // Restore input method and clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if needsSwitch {
                self?.inputMethodManager.restorePreviousInputSource()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.restorePasteboard(pasteboard, items: savedItems)
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        // keycode 9 = V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
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
