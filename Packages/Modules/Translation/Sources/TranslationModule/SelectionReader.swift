import Foundation

/// Text selected in another app, and the app it was selected in, which a translation can later replace it in.
nonisolated struct SelectionSource: Equatable, Sendable {
    var text: String
    var application: FocusedApplication
}

/// Reads the text selected in the frontmost app through Accessibility. Returns nil whenever it can't,
/// so the caller opens the tab empty.
final class SelectionReader {
    /// Lets Chromium and Electron apps build the accessibility tree they create lazily. Chromium then switches
    /// to screen-reader mode, so the user can turn this off.
    var useChromiumAccessibility = true

    private static let retryInterval = Duration.milliseconds(100)
    private static let retries = 6

    /// Attribute that makes each known app expose its selection, by bundle ID.
    static let accessibilityAttributes: [String: String] = {
        let chromium = [
            "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
            "org.chromium.Chromium",
            "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
            "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
            "company.thebrowser.Browser", "company.thebrowser.dia",
            "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.operasoftware.OperaGX",
        ]
        let electron = [
            "com.tinyspeck.slackmacgap", "com.hnc.Discord",
            "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
            "notion.id", "md.obsidian", "com.figma.Desktop", "com.linear", "com.postmanlabs.mac",
            "com.anthropic.claudefordesktop", "com.vng.zalo", "org.whispersystems.signal-desktop",
            "com.github.GitHubClient",
        ]
        return Dictionary(uniqueKeysWithValues: chromium.map { ($0, "AXEnhancedUserInterface") } + electron.map { ($0, "AXManualAccessibility") })
    }()

    private let accessibility: any AccessibilityClient
    private let pause: @MainActor (Duration) async throws -> Void
    /// Apps whose accessibility tree this reader already turned on: once built, waiting for it won't help.
    private var enabledApplications: Set<FocusedApplication> = []

    init(
        accessibility: any AccessibilityClient = SystemAccessibilityClient(),
        pause: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.accessibility = accessibility
        self.pause = pause
    }

    /// The app whose selection is read: the one with the keyboard focus, else the one in front. The system-wide element
    /// does not always say which app has the focus (it can answer "cannot complete" while the app in front reads fine), and
    /// MyNotch's own text fields don't count: the selection belongs to another app, which stays in front while the notch
    /// panel has the keyboard. Asked before the notch opens, since an open notch can take the focus.
    func targetApplication() -> FocusedApplication? {
        guard accessibility.isTrusted else { return nil }
        let ownProcessID = getpid()
        if let focused = accessibility.focusedApplication(), focused.processID != ownProcessID { return focused }
        return accessibility.frontmostApplication().flatMap { $0.processID == ownProcessID ? nil : $0 }
    }

    func selection() async -> SelectionSource? {
        await selection(in: targetApplication())
    }

    /// The selection in `application`, found by `targetApplication()`; nil when there is none.
    func selection(in application: FocusedApplication?) async -> SelectionSource? {
        guard accessibility.isTrusted, let application, application.processID != getpid() else { return nil }
        switch read(application) {
        case .text(let text): return SelectionSource(text: text, application: application)
        case .unresponsive: return nil
        case .empty: break
        }
        guard useChromiumAccessibility,
              let attribute = application.bundleID.flatMap({ Self.accessibilityAttributes[$0] }),
              !enabledApplications.contains(application) else { return nil }
        if !accessibility.isEnabled(attribute, in: application) {
            accessibility.enable(attribute, in: application)
        }
        enabledApplications.insert(application)
        // The app builds its tree asynchronously after the attribute is set.
        for _ in 0..<Self.retries {
            do {
                try await pause(Self.retryInterval)
            } catch {
                return nil   // cancelled
            }
            switch read(application) {
            case .text(let text): return SelectionSource(text: text, application: application)
            case .unresponsive: return nil
            case .empty: continue
            }
        }
        return nil
    }

    private func read(_ application: FocusedApplication) -> SelectionRead {
        let read = accessibility.readSelection(in: application)
        if case .text(let text) = read, text.allSatisfy(\.isWhitespace) { return .empty }
        return read
    }
}
