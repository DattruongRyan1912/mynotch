import Foundation

/// Which engine translates. Apple's runs on the Mac and is the default; the others need the user's own key, and send
/// the text being translated to that service, and only while they are the one chosen.
nonisolated enum EngineChoice: String, CaseIterable, Sendable {
    case apple
    case google
    case microsoft
    case openAI = "openai"

    /// The picker's row.
    var title: String {
        switch self {
        case .apple: "Apple (mặc định, trên máy)"
        case .google: "Google Cloud Translation"
        case .microsoft: "Microsoft Translator"
        case .openAI: "LLM tương thích OpenAI"
        }
    }

    /// How a message calls it.
    var name: String {
        self == .apple ? "Apple" : title
    }

    /// Where its key is kept; nil for the engine that needs none.
    var secret: TranslationSecret? {
        switch self {
        case .apple: nil
        case .google: .googleKey
        case .microsoft: .microsoftKey
        case .openAI: .openAIKey
        }
    }

    /// Shown under the picker.
    static let privacyNote = "Chỉ đoạn chữ cần dịch được gửi đi, và chỉ khi bạn chọn bộ máy đó; Apple không gửi gì."
}

/// The settings of the engines that are not secret: the Microsoft region, and the address and model of the language model.
nonisolated struct EngineConfig: Equatable, Sendable {
    var microsoftRegion = ""
    var openAIBaseURL = ""
    var openAIModel = ""
}
