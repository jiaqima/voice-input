import AppKit
import AVFoundation
import Speech

final class Permissions {
    static func requestAll() {
        requestMicrophone()
        requestSpeechRecognition()
        checkAccessibility()
    }

    private static func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    showAlert(
                        title: "Microphone Access Required",
                        message: "Please enable microphone access in System Settings > Privacy & Security > Microphone."
                    )
                }
            }
        }
    }

    private static func requestSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                DispatchQueue.main.async {
                    showAlert(
                        title: "Speech Recognition Required",
                        message: "Please enable speech recognition in System Settings > Privacy & Security > Speech Recognition."
                    )
                }
            }
        }
    }

    static func checkAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
