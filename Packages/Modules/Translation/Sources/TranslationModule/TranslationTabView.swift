import NotchUI
import SwiftUI

/// The "Dịch" tab: language menus on top, the text to translate on the left and the result on the right.
struct TranslationTabView: View {
    let state: TranslationState
    let translator: Translator
    let install: () -> Void

    @Environment(\.notch) private var notch
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            languageBar
            HStack(alignment: .top, spacing: 10) {
                inputBox
                outputBox
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(NotchTokens.primaryText)
        // The notch is always black, whatever the system appearance.
        .environment(\.colorScheme, .dark)
    }

    private var languageBar: some View {
        HStack(spacing: 6) {
            menuButton(sourceTitle, help: "Ngôn ngữ nguồn") {
                LanguageMenu.show(sourceEntries, notch: notch)
            }
            Button(action: translator.swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.canSwap ? NotchTokens.primaryText : NotchTokens.secondaryText)
            .disabled(!state.canSwap)
            .help("Đảo chiều dịch")
            menuButton(SupportedLanguages.name(of: state.target), help: "Ngôn ngữ đích") {
                LanguageMenu.show(targetEntries, notch: notch)
            }
            Spacer()
            if state.isTranslating {
                ProgressView().controlSize(.small)
            }
        }
        .font(.system(size: 12, weight: .medium))
    }

    private var sourceTitle: String {
        if let source = state.source { return SupportedLanguages.name(of: source) }
        return state.detectedSource.map { "Tự nhận diện · \(SupportedLanguages.name(of: $0))" } ?? "Tự nhận diện"
    }

    private var sourceEntries: [LanguageMenu.Entry] {
        let automatic = LanguageMenu.Entry.option(title: "Tự nhận diện", isSelected: state.source == nil) { translator.setSource(nil) }
        return [automatic, .separator] + state.languages.map { language in
            .option(title: SupportedLanguages.name(of: language), isSelected: Self.same(state.source, language)) {
                translator.setSource(language)
            }
        }
    }

    private var targetEntries: [LanguageMenu.Entry] {
        // Until the list loads, the menu at least shows the current target.
        (state.languages.isEmpty ? [state.target] : state.languages).map { language in
            .option(title: SupportedLanguages.name(of: language), isSelected: Self.same(state.target, language)) {
                translator.setTarget(language)
            }
        }
    }

    private var inputBox: some View {
        ZStack(alignment: .topLeading) {
            TranslationInputField(
                text: state.input,
                focusRequest: state.focusRequest,
                onEdit: translator.edit,
                onSubmit: translator.translate
            )
            if state.input.isEmpty {
                Text("Nhập văn bản, Return để dịch")
                    .foregroundStyle(NotchTokens.secondaryText)
                    .allowsHitTesting(false)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var outputBox: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let banner = state.banner {
                    bannerView(banner)
                } else if let error = state.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    ScrollView {
                        Text(state.output)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !state.output.isEmpty, state.banner == nil {
                copyButton
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func bannerView(_ banner: TranslationState.Banner) -> some View {
        switch banner {
        case .notInstalled(let pair):
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Chưa cài gói ngôn ngữ \(SupportedLanguages.name(of: pair.source))↔\(SupportedLanguages.name(of: pair.target))",
                    systemImage: "arrow.down.circle"
                )
                .foregroundStyle(NotchTokens.secondaryText)
                Button("Cài đặt…", action: install)
                    .buttonStyle(.borderedProminent)
                    .tint(NotchTokens.accent)
                    .controlSize(.small)
            }
        case .unsupported:
            Label("Cặp ngôn ngữ này không được hỗ trợ", systemImage: "nosign")
                .foregroundStyle(NotchTokens.secondaryText)
        }
    }

    private var copyButton: some View {
        Button {
            translator.copyOutput()
            copied = true
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .frame(width: 24, height: 22)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy bản dịch")
        .task(id: copied) {
            guard copied else { return }
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            copied = false
        }
    }

    private func menuButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Menu items come from Translation's list ("vi" there is Vietnamese in Vietnam), the setting is plain "vi".
    private static func same(_ lhs: Locale.Language?, _ rhs: Locale.Language) -> Bool {
        lhs?.minimalIdentifier == rhs.minimalIdentifier
    }
}
