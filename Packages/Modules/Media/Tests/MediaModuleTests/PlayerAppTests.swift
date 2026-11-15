import Testing
@testable import MediaModule

@Suite struct PlayerAppTests {
    @Test func browserKindIdentifiesSupportedBrowsers() {
        #expect(PlayerApp.browserKind(for: "com.google.Chrome") != nil)
        #expect(PlayerApp.browserKind(for: "com.brave.Browser") != nil)
        #expect(PlayerApp.browserKind(for: "com.microsoft.edgemac") != nil)
        #expect(PlayerApp.browserKind(for: "company.thebrowser.Browser") != nil)
        #expect(PlayerApp.browserKind(for: "com.apple.Safari") != nil)
        #expect(PlayerApp.browserKind(for: "com.spotify.client") == nil)
        #expect(PlayerApp.browserKind(for: "com.apple.Music") == nil)
    }

    @Test func escapeForAppleScriptCleansQuotesAndBackslashes() {
        let dirty = "Never \"Gonna\" Give \\ You \n Up"
        let clean = PlayerApp.escapeForAppleScript(dirty)
        #expect(clean == "Never \\\"Gonna\\\" Give \\\\ You   Up")
    }

    @Test func buildBrowserScriptChromiumGeneratesValidScript() {
        let script = PlayerApp.buildBrowserScript(
            kind: .chromium(bundleID: "com.google.Chrome"),
            title: "Never \"Gonna\" Give You Up - YouTube"
        )
        #expect(script.contains("tell application id \"com.google.Chrome\""))
        #expect(script.contains("youtube.com"))
        #expect(script.contains("Never \\\"Gonna\\\" Give You Up - YouTube"))
        #expect(script.contains("active tab index of w to tabIndex"))
    }

    @Test func buildBrowserScriptSafariGeneratesValidScript() {
        let script = PlayerApp.buildBrowserScript(
            kind: .safari(bundleID: "com.apple.Safari"),
            title: "Rick Astley"
        )
        #expect(script.contains("tell application id \"com.apple.Safari\""))
        #expect(script.contains("youtube.com"))
        #expect(script.contains("Rick Astley"))
        #expect(script.contains("current tab of w to t"))
    }

    @Test func buildBrowserScriptTreatsSoundCloudAsAPlayerTab() {
        for kind in [PlayerApp.BrowserKind.chromium(bundleID: "com.google.Chrome"), .safari(bundleID: "com.apple.Safari")] {
            let script = PlayerApp.buildBrowserScript(kind: kind, title: "Some Track")
            #expect(script.contains("tURL contains \"soundcloud.com\""))
            // A tab with the track's title beats a media tab without it.
            let title = script.range(of: "if matchTitleTab")!
            let media = script.range(of: "if matchTab")!
            #expect(title.lowerBound < media.lowerBound)
        }
    }
}
