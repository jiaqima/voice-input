import Carbon

final class InputMethodManager {
    private var savedInputSource: TISInputSource?

    func saveCurrentAndSwitchToASCII() {
        savedInputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()

        guard let asciiSource = findASCIIInputSource() else { return }

        let currentID = inputSourceID(savedInputSource)
        let asciiID = inputSourceID(asciiSource)
        if currentID != asciiID {
            TISSelectInputSource(asciiSource)
        }
    }

    func restorePreviousInputSource() {
        guard let source = savedInputSource else { return }
        TISSelectInputSource(source)
        savedInputSource = nil
    }

    static func isCJKInputMethodActive() -> Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return false
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        let cjkPrefixes = [
            "com.apple.inputmethod.SCIM",    // Simplified Chinese
            "com.apple.inputmethod.TCIM",    // Traditional Chinese
            "com.apple.inputmethod.Korean",  // Korean
            "com.apple.inputmethod.Japanese", // Japanese
            "com.apple.inputmethod.ChineseHandwriting",
            "com.google.inputmethod.Japanese",
            "com.sogou.inputmethod",
            "com.baidu.inputmethod",
            "com.tencent.inputmethod",
        ]
        return cjkPrefixes.contains(where: { sourceID.hasPrefix($0) })
    }

    private func findASCIIInputSource() -> TISInputSource? {
        let conditions = [
            kTISPropertyInputSourceCategory!: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsASCIICapable!: true,
            kTISPropertyInputSourceIsEnabled!: true,
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        // Prefer ABC or US keyboard
        for source in sources {
            let sid = inputSourceID(source) ?? ""
            if sid == "com.apple.keylayout.ABC" || sid == "com.apple.keylayout.US" {
                return source
            }
        }
        return sources.first
    }

    private func inputSourceID(_ source: TISInputSource?) -> String? {
        guard let source = source,
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
