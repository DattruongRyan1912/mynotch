import NotchUI
import SwiftUI

/// The word's entry from the Mac's dictionary, above its translation: the headword with its part of speech, the first
/// senses, and a button that opens Dictionary at the word.
struct DictionaryCardView: View {
    let entry: DictionaryEntry
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.headword)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let part = entry.partOfSpeech {
                    Text(part)
                        .font(.system(size: 11).italic())
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                }
            }
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { index, sense in
                Text(entry.senses.count > 1 ? "\(index + 1). \(sense)" : sense)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.primaryText.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: open) {
                Label("Mở trong Từ điển", systemImage: "book")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTokens.accent)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
