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
    /// The `EngineChoice` that translates, by raw value. The keys of the engines that need one are not settings at all:
    /// they live in the Keychain.
    let engine: SettingKey<String>
    /// The Microsoft resource's region, such as "southeastasia"; blank for a global resource.
    let microsoftRegion: SettingKey<String>
    /// Base address and model of the OpenAI-compatible server.
    let openAIBaseURL: SettingKey<String>
    let openAIModel: SettingKey<String>
    /// "Bôi đen là hiểu": a selection in any app is understood without a keystroke, and shown beside it. Needs Accessibility.
    let smartSelection: SettingKey<Bool>
    /// The small button beside the selection that shows what was understood.
    let selectionChip: SettingKey<Bool>
    /// What was understood is also shown as a short live activity beside the collapsed notch.
    let selectionActivity: SettingKey<Bool>
    /// Bundle IDs of the apps whose selections are never read.
    let selectionDenyList: SettingKey<[String]>

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
        engine = settings.key("engine", default: EngineChoice.apple.rawValue)
        microsoftRegion = settings.key("microsoftRegion", default: "")
        openAIBaseURL = settings.key("openAIBaseURL", default: "https://api.openai.com/v1")
        openAIModel = settings.key("openAIModel", default: "gpt-4o-mini")
        smartSelection = settings.key("smartSelection", default: true)
        selectionChip = settings.key("selectionChip", default: true)
        selectionActivity = settings.key("selectionActivity", default: false)
        selectionDenyList = settings.key("selectionDenyList", default: [])
    }
}
