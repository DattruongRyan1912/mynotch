/// Reads the text selected in the frontmost app through Accessibility. Returns nil whenever it can't,
/// so the caller opens the tab empty.
final class SelectionReader {
    /// Lets Chromium and Electron apps build the accessibility tree they create lazily. Chromium then switches
    /// to screen-reader mode, so the user can turn this off.
    var useChromiumAccessibility = true

    private static let retryInterval = Duration.milliseconds(100)
    private static let retries = 6

    /// Attribute that makes each known app expose its selection, by bundle ID.
    private static let accessibilityAttributes: [String: String] = {
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
            "com.github.GitHubClient", "com.1password.1password",
        ]
        return Dictionary(uniqueKeysWithValues: chromium.map { ($0, "AXEnhancedUserInterface") } + electron.map { ($0, "AXManualAccessibility") })
    }()

    private let accessibility: any AccessibilityClient
    private let pause: @MainActor (Duration) async throws -> Void

    init(
        accessibility: any AccessibilityClient = SystemAccessibilityClient(),
        pause: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.accessibility = accessibility
        self.pause = pause
    }

    func selectedText() async -> String? {
        guard accessibility.isTrusted, let application = accessibility.focusedApplication() else { return nil }
        if let text = read(application) { return text }
        guard useChromiumAccessibility,
              let attribute = application.bundleID.flatMap({ Self.accessibilityAttributes[$0] }) else { return nil }
        accessibility.enable(attribute, in: application)
        // The app builds its tree asynchronously after the attribute is set.
        for _ in 0..<Self.retries {
            do {
                try await pause(Self.retryInterval)
            } catch {
                return nil   // cancelled
            }
            if let text = read(application) { return text }
        }
        return nil
    }

    private func read(_ application: FocusedApplication) -> String? {
        guard let text = accessibility.selectedText(in: application),
              !text.allSatisfy(\.isWhitespace) else { return nil }
        return text
    }
}
