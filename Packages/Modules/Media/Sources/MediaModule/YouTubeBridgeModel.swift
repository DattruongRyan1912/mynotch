import AppKit
import Foundation
import Observation

/// What the Settings buttons work on, so tests can use temporary folders and a reveal that opens nothing.
struct YouTubeBridgeSetup {
    var installer: YouTubeBridgeInstaller
    /// Shows a folder in Finder.
    var reveal: (URL) -> Void

    static func system(storageDirectory: URL) -> YouTubeBridgeSetup {
        YouTubeBridgeSetup(
            installer: YouTubeBridgeInstaller(locations: .system(storageDirectory: storageDirectory)),
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        )
    }
}

/// What the Settings rows for the Chrome bridge show: whether it is installed, whether the extension has been heard
/// from in a YouTube page, what the last button did. The module keeps one for its whole life, and fills in
/// `lastPageMessageAt`, `accessWithheld` and `listenFailed` as it listens.
@Observable
final class YouTubeBridgeModel {
    enum Status: Equatable {
        case notInstalled
        case waiting
        case connected

        var text: String {
            switch self {
            case .notInstalled: "Chưa cài"
            case .waiting: "Đã cài — chờ extension"
            case .connected: "Extension đang kết nối"
            }
        }
    }

    /// What to do when Chrome has set the extension's site access to "On click" and so lets it read nothing on YouTube.
    static let accessWithheldMessage = "Chrome đang chặn extension đọc YouTube. Mở chrome://extensions, chọn MyNotch YouTube Bridge → Quyền truy cập trang web → Trên tất cả trang web, rồi tải lại tab YouTube."
    /// Why the skip buttons may do nothing for a YouTube video in Chrome: YouTube ignores the system's next and previous there.
    static let skipHint = "Nút chuyển bài cho YouTube cần extension MyNotch"
    static let listenFailureMessage = "Không mở được socket nhận phụ đề từ Chrome nên phụ đề YouTube chưa hoạt động. Tắt rồi bật lại để thử lại."
    /// The extension counts as connected while its last page message is no older than this; the page sends one every 5 s while a video plays.
    static let connectedWindow: TimeInterval = 30

    private(set) var message = ""
    private(set) var isInstalled = false
    /// When the module last got a message that shows the extension at work in a YouTube page (captions, playback, clear, or
    /// a diagnostic of the content or page script); nil while there has been none. The service worker's own diagnostics do
    /// not count: with Chrome withholding the site access they arrive while nothing reads YouTube.
    var lastPageMessageAt: Date?
    /// The socket for the host could not be opened.
    var listenFailed = false
    /// The extension said that Chrome withholds its access to YouTube. False until it says so, and again once it says the
    /// access is granted, once the page sends anything (which proves the access works, whatever was reported before), and
    /// when the bridge is removed.
    var accessWithheld = false

    @ObservationIgnored private var setup: YouTubeBridgeSetup?
    /// Runs after an install: captions come over the socket, which is open only while the setting is on.
    @ObservationIgnored private var didInstall: () -> Void = {}

    /// The first call wins: the rows are built again whenever the page refreshes, and a module that is not running
    /// still shows them. Nothing is read from disk until the rows appear (`refresh`).
    func configure(setup: YouTubeBridgeSetup, didInstall: @escaping () -> Void) {
        guard self.setup == nil else { return }
        self.setup = setup
        self.didInstall = didInstall
    }

    func status(at now: Date) -> Status {
        if let lastPageMessageAt, now.timeIntervalSince(lastPageMessageAt) <= Self.connectedWindow { return .connected }
        return isInstalled ? .waiting : .notInstalled
    }

    /// Looks at the disk: the files may have been removed by hand.
    func refresh() {
        let installed = setup?.installer.isInstalled ?? false
        if installed != isInstalled { isInstalled = installed }
    }

    func install() {
        guard let setup else {
            message = "Không cài được cầu nối: thiếu thông tin thư mục của module."
            return
        }
        do {
            try setup.installer.install()
            didInstall()
            setup.reveal(setup.installer.locations.installedExtension)
            message = "Đã cài cầu nối. Mở chrome://extensions, bật Developer mode, bấm Load unpacked rồi chọn thư mục ChromeExtension vừa hiện trong Finder."
        } catch {
            message = "Không cài được cầu nối: \(error.localizedDescription)"
        }
        refresh()
    }

    func remove() {
        guard let setup else {
            message = "Không gỡ được cầu nối: thiếu thông tin thư mục của module."
            return
        }
        do {
            try setup.installer.remove()
            // The notice is about an extension this bridge no longer serves.
            if accessWithheld { accessWithheld = false }
            message = "Đã gỡ cầu nối. Nhớ xoá extension trong chrome://extensions."
        } catch {
            message = "Không gỡ được cầu nối: \(error.localizedDescription)"
        }
        refresh()
    }
}
