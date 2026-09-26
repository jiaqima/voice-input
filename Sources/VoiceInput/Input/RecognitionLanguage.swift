import Foundation

/// What the speech recognizer should listen for.
enum RecognitionLanguage {
    /// A single fixed locale (existing behaviour).
    case locale(Locale)
    /// Whisper decides between Simplified Chinese and English per utterance,
    /// keeping English terms inside Chinese sentences.
    case autoChineseEnglish

    static let autoChineseEnglishSettingValue = "auto-zh-en"

    init(settingValue: String) {
        if settingValue == Self.autoChineseEnglishSettingValue {
            self = .autoChineseEnglish
        } else {
            self = .locale(Locale(identifier: settingValue))
        }
    }

    /// Locale used by backends that cannot do mixed-language recognition.
    var fallbackLocale: Locale {
        switch self {
        case .locale(let locale):
            return locale
        case .autoChineseEnglish:
            return Locale(identifier: "zh-CN")
        }
    }
}
