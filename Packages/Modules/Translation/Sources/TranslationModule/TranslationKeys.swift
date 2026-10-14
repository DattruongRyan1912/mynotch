import Foundation
import MyNotchCore

/// The two languages the user translates between most; the flip rule turns text in one into the other.
/// Stored as language identifiers ("vi", "en-GB"), so the setting stays readable.
nonisolated struct PreferredPair: Codable, Equatable, Sendable {
    var first: String
    var second: String

    var languages: (Locale.Language, Locale.Language) {
        (Locale.Language(identifier: first), Locale.Language(identifier: second))
    }
}

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct TranslationKeys {
    let preferredPair: SettingKey<PreferredPair>
    /// Identifier of the language the tab translates into, unless the flip rule picks the pair's other one.
    let targetLanguage: SettingKey<String>
    /// Translate text from the shortcut or Services as soon as the tab opens.
    let autoTranslateOnOpen: SettingKey<Bool>
    let useChromiumAccessibility: SettingKey<Bool>
    /// Offer "Thay vào chỗ đang chọn" on a result that came from a selection in another app.
    let showReplaceButton: SettingKey<Bool>
    /// Convert amounts of money, which needs the day's rates from the internet, so it starts off.
    let convertCurrency: SettingKey<Bool>
    /// ISO code of the currency amounts are converted into.
    let currencyTarget: SettingKey<String>
    /// The two time zones a time is also shown in, as IANA identifiers.
    let firstZone: SettingKey<String>
    let secondZone: SettingKey<String>

    init(_ settings: ModuleSettings) {
        preferredPair = settings.key("preferredPair", default: PreferredPair(first: "vi", second: "en"))
        targetLanguage = settings.key("targetLanguage", default: "vi")
        autoTranslateOnOpen = settings.key("autoTranslateOnOpen", default: true)
        useChromiumAccessibility = settings.key("useChromiumAccessibility", default: true)
        showReplaceButton = settings.key("showReplaceButton", default: true)
        convertCurrency = settings.key("convertCurrency", default: false)
        currencyTarget = settings.key("currencyTarget", default: "VND")
        firstZone = settings.key("conversionZoneFirst", default: "America/Los_Angeles")
        secondZone = settings.key("conversionZoneSecond", default: "Europe/London")
    }
}
