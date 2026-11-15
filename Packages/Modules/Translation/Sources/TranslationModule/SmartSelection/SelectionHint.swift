import Foundation

/// What the chip says about a selection: the converted value, or the start of its translation.
nonisolated struct SelectionHint: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case conversion
        case translation
        /// Foreign text whose preview could not be made: the chip is a "Dịch" button that opens the tab, and `text` is only the
        /// reason it needs ("Cần tải gói ngôn ngữ") or nothing.
        case button
        /// A selection that was read but not translated by itself, for a reason that is only a guess: just a small translate
        /// button, which opens the selection in the tab, translated. `text` is empty and `reason` says why it is offered.
        case translateButton

        /// What the log calls it.
        var logCode: String {
            switch self {
            case .conversion: "conversion"
            case .translation: "preview"
            case .button: "button"
            case .translateButton: "translate-button"
            }
        }
    }

    /// The button's note when the language pack is not installed.
    static let languagePackNote = "Cần tải gói ngôn ngữ"
    /// What the button chip and its activity say.
    static let buttonTitle = "Dịch"
    /// Beside the button of a preview that translated only the start of a long selection.
    static let partialNote = "Mở để dịch đủ"

    /// A conversion is one line in the chip; longer is cut here. A translation is never cut: the chip wraps and scrolls it.
    static let maxLength = 80
    /// The first line of the original, small, over a translation.
    static let captionLength = 60

    var kind: Kind
    /// A conversion: one line, no longer than `maxLength`. A translation: all of it, trimmed, in as many lines as it has. A
    /// button: its note, or empty.
    var text: String
    /// The selection it was made for, which "Mở" opens in the tab and the replace button writes over.
    var source: SelectionSource
    /// Set when only the start of the selection was translated: the translation then ends with "…" and the chip says that
    /// "Mở" translates all of it.
    var note: String?
    /// For the small translate button: why the selection was not translated by itself.
    var reason: SelectionSkip?

    /// The first line of the original text, for the small caption over its translation; nil when it has none.
    static func caption(of original: String) -> String? {
        original.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { $0.count > captionLength ? String($0.prefix(captionLength - 1)).trimmingCharacters(in: .whitespaces) + "…" : $0 }
    }

    /// The first line that has anything on it, trimmed, with an ellipsis if it had to be cut.
    static func firstLine(of text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map(shortened)
    }

    static func shortened(_ line: String) -> String {
        guard line.count > maxLength else { return line }
        return String(line.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "5 ft 11 in → 180 cm", "(2+3)*4 = 20", or "3pm PST → Giờ máy · UTC+7: 06:00" for the first result of the conversion;
    /// nil when it has none yet or failed.
    static func conversionText(_ conversion: Conversion) -> String? {
        guard case .lines(let lines) = conversion.outcome, let line = lines.first else { return nil }
        let answer = line.label.map { "\($0): \(line.text)" } ?? line.text
        return conversion.source.hasSuffix(" =") ? "\(conversion.source) \(answer)" : "\(conversion.source) → \(answer)"
    }
}
