import AppKit
import WebKit

/// What the module needs from the sign-in window. A protocol so tests never open a web view or touch web data.
protocol AppleMusicSignIn {
    /// Shows the window, or brings the open one forward. `connect` is called with the credentials once the page has them,
    /// and the window closes when it answers. `closed` is called once when the window is gone, whoever closed it.
    func open(connect: @escaping (AppleMusicCredentials) async -> Bool, closed: @escaping () async -> Void)
    func close()
    /// Deletes the cookies and everything else the window's web view stored.
    func removeWebsiteData() async
}

/// A window with the Apple Music web player, where the user signs in themselves: the app never sees the password,
/// only the tokens the page ends up with. AppKit glue; what is read from the page is decided by `AppleMusicSessionReader`,
/// and what happens to the web session afterwards by the module (it asks for it to be wiped when the window is gone).
final class AppleMusicLoginWindow: NSObject, AppleMusicSignIn, NSWindowDelegate {
    static let title = "Đăng nhập Apple Music"
    static let startURL = URL(string: "https://music.apple.com/")!
    static let contentSize = NSSize(width: 480, height: 680)
    static let pollInterval: Duration = .seconds(1)
    /// A data store of its own, found again after a restart: the sign-in and its cookies never mix with other web
    /// views, and disconnecting can wipe them without touching anything else.
    static let dataStoreID = UUID(uuidString: "6F0C3B1E-7A52-4D0B-9C44-2E5D0B7A1C31")!

    private var window: NSWindow?
    private var webView: WKWebView?
    private var polling: Task<Void, Never>?
    private var closed: (() async -> Void)?

    func open(connect: @escaping (AppleMusicCredentials) async -> Bool, closed: @escaping () async -> Void) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreID)
        // Without a Safari-like name the page may take this for an unsupported browser.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        let webView = WKWebView(frame: NSRect(origin: .zero, size: Self.contentSize), configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = Self.title
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.webView = webView
        self.closed = closed
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        polling = Task { [weak self] in
            // A session an earlier window left (the app quit with it open) is not reused: every sign-in starts clean.
            await self?.removeWebsiteData()
            self?.webView?.load(URLRequest(url: Self.startURL))
            // The page gives no signal when the user is done, so look about once a second until both tokens are there.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self else { return }
                guard !Task.isCancelled, let credentials = await credentialsOnThePage(), !Task.isCancelled else { continue }
                _ = await connect(credentials)
                close()
                return
            }
        }
    }

    func close() {
        polling?.cancel()
        window?.close()
    }

    func removeWebsiteData() async {
        let store = WKWebsiteDataStore(forIdentifier: Self.dataStoreID)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    func windowWillClose(_ notification: Notification) {
        polling?.cancel()
        polling = nil
        webView?.stopLoading()
        webView = nil
        window = nil
        let closed = closed
        self.closed = nil
        if let closed { Task { await closed() } }
    }

    private func credentialsOnThePage() async -> AppleMusicCredentials? {
        guard let webView else { return nil }
        let result = try? await webView.evaluateJavaScript(AppleMusicSessionReader.script) as? String
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return AppleMusicSessionReader.credentials(scriptResult: result, cookies: cookies)
    }
}
