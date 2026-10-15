import Foundation

/// What the chip says about a selection: the converted value, or the start of its translation.
nonisolated struct SelectionHint: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case conversion
        case translation
    }

    /// The chip shows one line; longer is cut here.
    static let maxLength = 80

    var kind: Kind
    /// Already one line and no longer than `maxLength`.
    var text: String
    /// The selection it was made for, which "Mở" opens in the tab and the replace button writes over.
    var source: SelectionSource

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
