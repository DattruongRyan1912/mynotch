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
/// from, what the last button did. The module keeps one for its whole life, and fills in `lastMessageAt` and
/// `listenFailed` as it listens.
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

    static let listenFailureMessage = "Không mở được socket nhận phụ đề từ Chrome nên phụ đề YouTube chưa hoạt động. Tắt rồi bật lại để thử lại."
    /// The extension counts as connected while its last message is no older than this; the page sends one every 5 s while a video plays.
    static let connectedWindow: TimeInterval = 30

    private(set) var message = ""
    private(set) var isInstalled = false
    /// When the module last got a message from the extension; nil while there has been none.
    var lastMessageAt: Date?
    /// The socket for the host could not be opened.
    var listenFailed = false

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
        if let lastMessageAt, now.timeIntervalSince(lastMessageAt) <= Self.connectedWindow { return .connected }
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
            message = "Đã gỡ cầu nối. Nhớ xoá extension trong chrome://extensions."
        } catch {
            message = "Không gỡ được cầu nối: \(error.localizedDescription)"
        }
        refresh()
    }
}
