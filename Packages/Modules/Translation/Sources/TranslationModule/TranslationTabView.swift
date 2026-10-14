import NotchUI
import SwiftUI

/// What the tab's buttons ask of the module.
struct TranslationTabActions {
    let install: () -> Void
    let replace: () -> Void
    let requestAccessibility: () -> Void
    let refreshAccessibility: () -> Void
}

/// The "Dịch" tab: language menus on top, the text to translate on the left and the result on the right. Under them,
/// when the text came from a selection in another app, the button that puts the result in its place.
struct TranslationTabView: View {
    let state: TranslationState
    let translator: Translator
    let speech: SpeechPlayer
    let actions: TranslationTabActions

    @Environment(\.notch) private var notch
    @State private var copied = false
    /// After a language pick the notch stays pinned until the pointer is back in it or `menuHold` passes, so the
    /// new translation can be seen even with the pointer left where the menu was.
    @State private var holdsOpen = false
    @State private var holdRequest = 0
    private static let menuHold = Duration.seconds(1.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            languageBar
            HStack(alignment: .top, spacing: 10) {
                inputBox
                outputBox
            }
            replaceBar
        }
        .font(.system(size: 13))
        .foregroundStyle(NotchTokens.primaryText)
        // The notch is always black, whatever the system appearance.
        .environment(\.colorScheme, .dark)
        .onHover { inside in
            if inside { releaseHold() }
        }
        .task(id: holdRequest) {
            guard holdsOpen else { return }
            do {
                try await Task.sleep(for: Self.menuHold)
            } catch {
                return
            }
            releaseHold()
        }
        // The system voices can change while the app runs.
        .onAppear(perform: speech.refreshVoices)
        // While the tab is shown: when it appears, then every 2 s, so the hint goes by itself once Accessibility is allowed.
        .task {
            while !Task.isCancelled {
                actions.refreshAccessibility()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
        // Switching tabs must not leave the notch pinned, nor a voice reading to nobody.
        .onDisappear {
            releaseHold()
            speech.stop()
        }
    }

    private var languageBar: some View {
        HStack(spacing: 6) {
            menuButton(sourceTitle, help: "Ngôn ngữ nguồn") {
                showMenu(sourceEntries)
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
                showMenu(targetEntries)
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
                onSubmit: translator.submit
            )
            if state.input.isEmpty {
                Text(state.isReadingSelection ? "Đang đọc đoạn chữ…" : "Nhập văn bản, Return để dịch")
                    .foregroundStyle(NotchTokens.secondaryText)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !state.input.isEmpty {
                speakButton(.original, text: state.input, language: state.currentPair?.source)
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
                HStack(spacing: 4) {
                    speakButton(.translation, text: state.output, language: state.target)
                    copyButton
                }
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
                Button("Cài đặt…", action: actions.install)
                    .buttonStyle(.borderedProminent)
                    .tint(NotchTokens.accent)
                    .controlSize(.small)
            }
        case .unsupported:
            Label("Cặp ngôn ngữ này không được hỗ trợ", systemImage: "nosign")
                .foregroundStyle(NotchTokens.secondaryText)
        }
    }

    /// One line under the boxes, only for a result that came from a selection in another app.
    @ViewBuilder private var replaceBar: some View {
        if state.showsReplace {
            HStack(spacing: 8) {
                if state.needsAccessibility {
                    accessibilityHint
                } else {
                    Button(action: actions.replace) {
                        Text("Thay vào chỗ đang chọn")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NotchTokens.accent)
                    .controlSize(.small)
                    .disabled(!state.canReplace)
                    if state.isReplacing {
                        ProgressView().controlSize(.small)
                    }
                }
                if let failure = state.replaceFailure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
        }
    }

    private var accessibilityHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Cần quyền Accessibility để thay vào chỗ đang chọn")
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
            Button {
                actions.requestAccessibility()
                // The system's dialog and System Settings come up over the notch, which would close on its own anyway.
                notch.close()
            } label: {
                Text("Cấp quyền")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(NotchTokens.accent.opacity(0.7), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Reads `text` aloud, or stops when it is the text being read. Off while no voice of its language is installed.
    private func speakButton(_ part: SpokenText, text: String, language: Locale.Language?) -> some View {
        let isSpeaking = speech.speaking == part
        let canSpeak = speech.canSpeak(language)
        return Button {
            speech.toggle(part, text: text, language: language)
        } label: {
            iconLabel(isSpeaking ? "stop.fill" : "speaker.wave.2")
        }
        .buttonStyle(.plain)
        .disabled(!isSpeaking && !canSpeak)
        .help(isSpeaking ? "Dừng đọc" : canSpeak ? "Đọc to" : "Máy chưa có giọng đọc cho ngôn ngữ này")
    }

    private func iconLabel(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .frame(width: 24, height: 22)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }

    private var copyButton: some View {
        Button {
            translator.copyOutput()
            copied = true
        } label: {
            iconLabel(copied ? "checkmark" : "doc.on.doc")
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
        // With keyboard navigation on, Space already presses a focused button; Return opens the menu too.
        .onKeyPress(.return) {
            action()
            return .handled
        }
    }

    private func showMenu(_ entries: [LanguageMenu.Entry]) {
        guard LanguageMenu.show(entries, notch: notch) else { return }
        holdsOpen = true
        holdRequest += 1
    }

    private func releaseHold() {
        guard holdsOpen else { return }
        holdsOpen = false
        notch.setPinned(false)
    }

    /// Menu items come from Translation's list ("vi" there is Vietnamese in Vietnam), the setting is plain "vi".
    private static func same(_ lhs: Locale.Language?, _ rhs: Locale.Language) -> Bool {
        lhs?.minimalIdentifier == rhs.minimalIdentifier
    }
}
