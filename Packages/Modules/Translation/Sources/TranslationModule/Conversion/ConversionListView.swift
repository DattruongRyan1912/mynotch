import NotchUI
import SwiftUI

/// What the quick convert found, shown above the translation: each quantity with its results, and a copy button on
/// every result.
struct ConversionListView: View {
    let conversions: [Conversion]
    /// The conversions share the box with a translation, so each result takes one line with its quantity and the
    /// translation stays in view. Otherwise they are the whole answer and get room.
    let isCompact: Bool
    let copy: (String) -> Void

    /// The result whose copy button was just pressed, shown as a check mark for a moment.
    @State private var copied: String?

    /// Whether to head each quantity with the text it was read from. The input box above already says it when it is
    /// the only quantity and the whole text.
    private var showsSource: Bool { isCompact || conversions.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
            ForEach(Array(conversions.enumerated()), id: \.offset) { index, conversion in
                block(conversion, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: copied) {
            guard copied != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            copied = nil
        }
    }

    @ViewBuilder private func block(_ conversion: Conversion, index: Int) -> some View {
        if isCompact, case .lines(let lines) = conversion.outcome, lines.count == 1, lines[0].label == nil {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    // One text, so a long quantity shrinks together with its result instead of crowding it out.
                    Text(Self.inlineText(source: conversion.source, result: lines[0].text))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    copyButton(lines[0].text, id: "\(index).0")
                }
                footnote(conversion, at: index)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if showsSource {
                    Text(conversion.source)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                }
                switch conversion.outcome {
                case .lines(let lines):
                    ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                        row(line, id: "\(index).\(lineIndex)")
                    }
                case .fetching:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Đang lấy tỷ giá…")
                    }
                    .foregroundStyle(NotchTokens.secondaryText)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                footnote(conversion, at: index)
            }
        }
    }

    /// One result with its label above, for a quantity that has several or needs saying what they are.
    private func row(_ line: ConversionLine, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = line.label {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .lineLimit(1)
            }
            result(line, id: id, size: 14)
        }
    }

    /// The text of one result and its copy button.
    private func result(_ line: ConversionLine, id: String, size: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(line.text)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 4)
            copyButton(line.text, id: id)
        }
    }

    private func copyButton(_ text: String, id: String) -> some View {
        Button {
            copy(text)
            copied = id
        } label: {
            Image(systemName: copied == id ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .frame(width: 22, height: 20)
                // The chip is black on any look, so its icon is light on it.
                .notchOnDarkBackground()
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy \(text)")
    }

    /// How a time was read, or the rates' date with the credit their source asks for, as a link. Amounts that share
    /// the same rates share one footnote, under the first of them.
    @ViewBuilder private func footnote(_ conversion: Conversion, at index: Int) -> some View {
        if Self.showsFootnote(of: conversions, at: index) {
            Text(Self.footnoteText(conversion))
                .font(.system(size: 10))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(2)
        }
    }

    /// Whether `conversions[index]` has a footnote to show: it has one, and no earlier conversion has the same.
    static func showsFootnote(of conversions: [Conversion], at index: Int) -> Bool {
        let conversion = conversions[index]
        guard conversion.note != nil || conversion.creditsRates else { return false }
        return conversions.firstIndex { $0.note == conversion.note && $0.creditsRates == conversion.creditsRates } == index
    }

    /// "12 USD → 300.000 ₫": the quantity quiet, the result bold.
    static func inlineText(source: String, result: String) -> AttributedString {
        var text = AttributedString(source + "  →  ")
        text.font = .system(size: 11)
        text.foregroundColor = NotchTokens.secondaryText
        var answer = AttributedString(result)
        answer.font = .system(size: 13, weight: .semibold)
        answer.foregroundColor = NotchTokens.primaryText
        text.append(answer)
        return text
    }

    static func footnoteText(_ conversion: Conversion) -> AttributedString {
        var text = AttributedString(conversion.note ?? "")
        if conversion.creditsRates {
            var credit = AttributedString("Rates By Exchange Rate API")
            credit.link = URL(string: "https://www.exchangerate-api.com")
            if !text.characters.isEmpty { text.append(AttributedString(" · ")) }
            text.append(credit)
        }
        return text
    }
}
