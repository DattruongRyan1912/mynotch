import SwiftUI

/// The text of a code item, monospaced and coloured by its language. The colours come from the shared cache: a small text
/// is coloured at once, a larger one shows plain until a background task has coloured it.
struct ClipboardCodeText: View {
    /// What is shown, already cut to a few lines by the card.
    let text: String
    let language: CodeLanguage
    let palette: CodePalette
    let size: CGFloat
    let lines: Int
    let color: Color

    @State private var loaded: (key: CodeHighlightCache.Key, text: AttributedString)?

    var body: some View {
        let key = CodeHighlightCache.Key(text: text, language: language, palette: palette)
        let colored = CodeHighlightCache.shared.immediate(key) ?? loaded.flatMap { $0.key == key ? $0.text : nil }
        Text(colored ?? AttributedString(text))
            .font(.system(size: size, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(lines)
            .task(id: key) {
                guard colored == nil else { return }
                loaded = (key, await CodeHighlightCache.shared.highlighted(key))
            }
    }
}
