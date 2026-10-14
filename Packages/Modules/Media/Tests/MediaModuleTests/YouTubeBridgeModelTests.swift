import Foundation
import MyNotchTestSupport
import Testing
@testable import MediaModule

@Suite final class YouTubeBridgeModelTests {
    let root = ScratchFolders.shared.reserve("youtube-model")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let model = YouTubeBridgeModel()
    var revealed: [URL] = []
    var installs = 0

    var locations: YouTubeBridgeInstaller.Locations {
        YouTubeBridgeInstaller.Locations(
            bundledHost: root.appending(path: "bundle/mynotch-youtube-host"),
            bundledExtension: root.appending(path: "bundle/ChromeExtension", directoryHint: .isDirectory),
            installedHost: root.appending(path: "support/bin/mynotch-youtube-host"),
            installedExtension: root.appending(path: "support/ChromeExtension", directoryHint: .isDirectory),
            nativeMessagingHosts: root.appending(path: "chrome/NativeMessagingHosts", directoryHint: .isDirectory)
        )
    }

    func makeBundle() throws {
        let locations = locations
        try FileManager.default.createDirectory(at: locations.bundledExtension, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: locations.bundledExtension.appending(path: "manifest.json"))
        try Data("#!/bin/sh\n".utf8).write(to: locations.bundledHost)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locations.bundledHost.path)
    }

    func configure() {
        model.configure(
            setup: YouTubeBridgeSetup(installer: YouTubeBridgeInstaller(locations: locations), reveal: { [self] in revealed.append($0) }),
            didInstall: { [self] in installs += 1 }
        )
    }

    // MARK: status

    @Test func theStatusSaysNotInstalledThenWaitingThenConnected() throws {
        try makeBundle()
        configure()
        #expect(model.status(at: now) == .notInstalled)
        #expect(model.status(at: now).text == "Chưa cài")

        model.install()
        #expect(model.status(at: now) == .waiting)
        #expect(model.status(at: now).text == "Đã cài — chờ extension")

        model.lastPageMessageAt = now
        #expect(model.status(at: now + 29.9) == .connected)
        #expect(model.status(at: now + 29.9).text == "Extension đang kết nối")
        #expect(model.status(at: now + 30) == .connected)
        #expect(model.status(at: now + 30.1) == .waiting)
    }

    @Test func aMessageProvesTheBridgeWorksEvenIfItWasInstalledByHand() {
        configure()
        model.lastPageMessageAt = now
        #expect(model.status(at: now + 5) == .connected)
    }

    @Test func withoutASetupNothingIsInstalledAndTheButtonsSayWhy() {
        #expect(model.status(at: now) == .notInstalled)
        model.install()
        #expect(model.message.hasPrefix("Không cài được cầu nối"))
        model.remove()
        #expect(model.message.hasPrefix("Không gỡ được cầu nối"))
    }

    // MARK: install and remove

    @Test func installPutsTheBridgeInPlaceRevealsTheExtensionFolderAndSwitchesTheSettingOn() throws {
        try makeBundle()
        configure()
        model.install()
        #expect(model.isInstalled)
        #expect(FileManager.default.fileExists(atPath: locations.manifest.path))
        #expect(revealed == [locations.installedExtension])
        #expect(installs == 1)
        #expect(model.message == "Đã cài cầu nối. Mở chrome://extensions, bật Developer mode, bấm Load unpacked rồi chọn thư mục ChromeExtension vừa hiện trong Finder.")
    }

    @Test func aFailedInstallSaysSoAndRevealsNothing() {
        configure()
        model.install()
        #expect(!model.isInstalled)
        #expect(revealed.isEmpty)
        #expect(installs == 0)
        #expect(model.message.hasPrefix("Không cài được cầu nối: Không tìm thấy "))
        #expect(!FileManager.default.fileExists(atPath: locations.nativeMessagingHosts.path))
    }

    @Test func removeTakesTheBridgeAwayAndRemindsToRemoveTheExtensionInChrome() throws {
        try makeBundle()
        configure()
        model.install()
        model.remove()
        #expect(!model.isInstalled)
        #expect(!FileManager.default.fileExists(atPath: locations.manifest.path))
        #expect(!FileManager.default.fileExists(atPath: locations.installedHost.path))
        #expect(model.message == "Đã gỡ cầu nối. Nhớ xoá extension trong chrome://extensions.")
    }

    @Test func refreshLooksAtTheDiskAgain() throws {
        try makeBundle()
        configure()
        model.install()
        try FileManager.default.removeItem(at: locations.manifest)
        #expect(model.isInstalled)
        model.refresh()
        #expect(!model.isInstalled)
    }

    @Test func aSetupThatIsAlreadyThereIsNotReplaced() throws {
        try makeBundle()
        configure()
        let other = YouTubeBridgeSetup(installer: YouTubeBridgeInstaller(locations: locations), reveal: { _ in Issue.record("replaced") })
        model.configure(setup: other, didInstall: {})
        model.install()
        #expect(revealed.count == 1)
        #expect(installs == 1)
    }

    // MARK: access withheld

    @Test func chromeWithholdingTheAccessIsOffUntilTheExtensionSaysSoAndItsNoticeTellsWhatToDo() {
        #expect(!model.accessWithheld)
        #expect(
            YouTubeBridgeModel.accessWithheldMessage
                == "Chrome đang chặn extension đọc YouTube. Mở chrome://extensions, chọn MyNotch YouTube Bridge → Quyền truy cập trang web → Trên tất cả trang web, rồi tải lại tab YouTube."
        )
    }

    @Test func theStatusIsTheSameWhetherOrNotChromeWithholdsTheAccess() throws {
        try makeBundle()
        configure()
        model.install()
        model.accessWithheld = true
        #expect(model.status(at: now) == .waiting)
        model.lastPageMessageAt = now
        #expect(model.status(at: now + 1) == .connected)
    }

    @Test func removingTheBridgeClearsTheWithheldNotice() throws {
        try makeBundle()
        configure()
        model.install()
        model.accessWithheld = true
        model.remove()
        #expect(!model.accessWithheld)
    }

    @Test func aRemoveThatFailsLeavesTheNoticeAlone() throws {
        // The folder that holds Chrome's manifest cannot be changed, so nothing is removed and the notice still holds.
        try makeBundle()
        configure()
        model.install()
        model.accessWithheld = true
        let folder = locations.nativeMessagingHosts
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        model.remove()
        #expect(model.message.hasPrefix("Không gỡ được cầu nối: "))
        #expect(model.accessWithheld)
    }

    // MARK: strings

    @Test func theRowsSayWhatTheyDoAndWhatLeavesTheMac() {
        #expect(YouTubeBridgeRows.title == "Phụ đề YouTube làm lời")
        #expect(
            YouTubeBridgeRows.title + ": " + YouTubeBridgeRows.explanation
                == "Phụ đề YouTube làm lời: khi bạn bật phụ đề (CC) trên YouTube trong Chrome, extension MyNotch chuyển phụ đề đó sang notch. Không có gì được gửi lên mạng."
        )
        #expect(YouTubeBridgeRows.installTitle == "Cài cầu nối cho Chrome")
        #expect(YouTubeBridgeRows.removeTitle == "Gỡ cầu nối")
        #expect(YouTubeBridgeModel.skipHint == "Nút chuyển bài cho YouTube cần extension MyNotch")
        #expect(YouTubeBridgeModel.listenFailureMessage == "Không mở được socket nhận phụ đề từ Chrome nên phụ đề YouTube chưa hoạt động. Tắt rồi bật lại để thử lại.")
    }
}
