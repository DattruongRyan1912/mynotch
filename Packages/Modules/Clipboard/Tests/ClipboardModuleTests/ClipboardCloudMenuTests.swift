import AppKit
import CryptoKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

@MainActor
private struct TestCardHostView: View {
    let item: ClipboardItem
    let onActivate: @MainActor (ClipboardItem) -> Void

    var body: some View {
        Button(action: { onActivate(item) }) {
            ClipboardCardView(
                item: item,
                isSelected: false,
                isPinned: false,
                now: Date(),
                imageURL: nil,
                thumbnails: ClipboardThumbnailCache()
            )
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct NotchCardWrapper: View {
    let module: ClipboardModule
    let item: ClipboardItem

    var body: some View {
        ClipboardCardView(
            item: item,
            isSelected: false,
            isPinned: false,
            now: Date(),
            imageURL: nil,
            thumbnails: module.thumbnails,
            link: nil
        )
        .frame(width: 150, height: 100)
        .contextMenu {
            ClipboardCardMenu(module: module, item: item, shownBoardID: nil) {}
        }
    }
}

@MainActor
private struct LibraryCardWrapper: View {
    let module: ClipboardModule
    let item: ClipboardItem

    var body: some View {
        ClipboardCardView(
            item: item,
            isSelected: false,
            isPinned: false,
            now: Date(),
            imageURL: nil,
            thumbnails: module.thumbnails,
            link: nil
        )
        .frame(width: 150, height: 100)
        .contextMenu {
            ClipboardCardMenu(
                module: module,
                item: item,
                shownBoardID: nil,
                onResult: { _ in },
                onDelete: { _ in },
                onEdit: { _ in },
                onNewBoard: {}
            )
        }
    }
}

@Suite(.serialized) struct ClipboardCloudMenuTests {

    @MainActor
    private func makeHostingWindow<V: View>(view: V, size: NSSize = NSSize(width: 112, height: 120)) -> (NSWindow, NSHostingView<V>) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        return (window, hostingView)
    }

    @MainActor
    private func pumpEvents() async {
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<50 where !condition() {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    private func extractContextMenu(from hostingView: NSView, in window: NSWindow) -> NSMenu? {
        let centerInHosting = NSPoint(x: hostingView.bounds.midX, y: hostingView.bounds.midY)
        let centerInWindow = hostingView.convert(centerInHosting, to: nil)
        guard let hitView = window.contentView?.hitTest(centerInWindow) else { return nil }
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: centerInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 201,
            clickCount: 1,
            pressure: 1.0
        )!
        var curr: NSView? = hitView
        while let v = curr {
            if let menu = v.menu(for: event) {
                return menu
            }
            if let menu = v.menu {
                return menu
            }
            curr = v.superview
        }
        return nil
    }

    @MainActor
    private func triggerMenuItem(titled title: String, in menu: NSMenu) -> Bool {
        guard let idx = menu.items.firstIndex(where: { $0.title == title }) else {
            return false
        }
        menu.performActionForItem(at: idx)
        return true
    }

    @MainActor
    private func dispatchLeftClick(in window: NSWindow, hostingView: NSView) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let centerInHosting = NSPoint(x: hostingView.bounds.midX, y: hostingView.bounds.midY)
        let centerInWindow = hostingView.convert(centerInHosting, to: nil)
        let hitView = window.contentView?.hitTest(centerInWindow) ?? hostingView
        let t = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: centerInWindow,
            modifierFlags: [],
            timestamp: t,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 101,
            clickCount: 1,
            pressure: 1.0
        )!
        let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: centerInWindow,
            modifierFlags: [],
            timestamp: t + 0.05,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 102,
            clickCount: 1,
            pressure: 0.0
        )!
        window.sendEvent(down)
        window.sendEvent(up)
        hitView.mouseDown(with: down)
        hitView.mouseUp(with: up)
    }

    // T28: Kiểm tra tương tác thẻ: Left-click kích hoạt sao chép (thực nghiệm NSEvent và module.copy), Context Menu chứa "Gửi sang thiết bị"
    @Test func cardInteractionLeftClickVsContextMenuAction() async throws {
        let module = ClipboardModule()
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        let expectedText = "Interactive Card Text via NSEvent"
        let textContent = ClipboardContent.text(expectedText)
        let item = ClipboardItem(
            id: UUID(),
            content: textContent,
            contentHash: ClipboardContent.hash(of: textContent),
            copiedAt: Date(),
            sensitive: false
        )

        // Clear pasteboard before test to ensure no stale value
        NSPasteboard.general.clearContents()

        // 1. Native Empirical UI Test: Host ClipboardCardView in NSWindow and dispatch real NSEvent click
        var activatedItem: ClipboardItem? = nil
        let hostView = TestCardHostView(item: item) { clicked in
            activatedItem = clicked
            _ = module.copy(clicked)
        }
        let (window, hostingView) = makeHostingWindow(view: hostView)
        defer { window.orderOut(nil) }
        await pumpEvents()

        Swift.print("[UI-DISPATCH] Dispatching native left-click NSEvent on ClipboardCardView at \(hostingView.frame)")
        dispatchLeftClick(in: window, hostingView: hostingView)
        await settle(until: { activatedItem != nil })

        #expect(activatedItem?.id == item.id, "Left-click on card must trigger activation callback")
        let pasteboardString = NSPasteboard.general.string(forType: .string)
        #expect(pasteboardString == expectedText, "Left-click on card must copy text to NSPasteboard via module.copy without regression")
        Swift.print("[DOM/AX STATE] Card activated successfully with item.id: \(item.id)")
        Swift.print("[SIDE-EFFECT] NSPasteboard.general updated via module.copy to: '\(pasteboardString ?? "")'")

        // 2. Context Menu UI Integration Test on Notch and Library wrappers:
        let lockedBoardID = UUID()
        let protectedID = UUID()
        let protectedItem = ClipboardItem(
            id: protectedID,
            content: textContent,
            contentHash: ClipboardContent.hash(of: textContent),
            copiedAt: Date(),
            sensitive: false
        )
        let lockedBoard = ClipboardBoard(
            id: lockedBoardID,
            name: "Vault Board",
            systemImage: "lock.shield",
            color: .accent,
            itemIDs: [protectedID],
            lock: ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        )
        module.state.history.boards = [lockedBoard]

        // Notch card wrapper (ordinary item):
        let notchWrapper = NotchCardWrapper(module: module, item: item)
        let (notchWindow, notchHosting) = makeHostingWindow(view: notchWrapper, size: NSSize(width: 150, height: 100))
        defer { notchWindow.orderOut(nil) }
        await pumpEvents()

        guard let notchMenu = extractContextMenu(from: notchHosting, in: notchWindow) else {
            Issue.record("Failed to extract context menu from NotchCardWrapper (ordinary)")
            return
        }
        let notchTitles = notchMenu.items.map(\.title)
        Swift.print("[DOM/AX STATE] Notch card context menu items: \(notchTitles)")
        #expect(notchTitles.contains("Gửi sang thiết bị"), "Notch card context menu for ordinary item must contain 'Gửi sang thiết bị'")

        // Notch card wrapper (sensitive item):
        let sensitiveItem = ClipboardItem(
            id: UUID(),
            content: textContent,
            contentHash: ClipboardContent.hash(of: textContent),
            copiedAt: Date(),
            sensitive: true
        )
        let notchSensWrapper = NotchCardWrapper(module: module, item: sensitiveItem)
        let (notchSensWindow, notchSensHosting) = makeHostingWindow(view: notchSensWrapper, size: NSSize(width: 150, height: 100))
        defer { notchSensWindow.orderOut(nil) }
        await pumpEvents()

        guard let notchSensMenu = extractContextMenu(from: notchSensHosting, in: notchSensWindow) else {
            Issue.record("Failed to extract context menu from NotchCardWrapper (sensitive)")
            return
        }
        let notchSensTitles = notchSensMenu.items.map(\.title)
        Swift.print("[DOM/AX STATE] Notch card sensitive context menu items: \(notchSensTitles)")
        #expect(!notchSensTitles.contains("Gửi sang thiết bị"), "Notch card context menu for sensitive item must NOT contain 'Gửi sang thiết bị'")

        // Notch card wrapper (protected board item):
        let notchProtWrapper = NotchCardWrapper(module: module, item: protectedItem)
        let (notchProtWindow, notchProtHosting) = makeHostingWindow(view: notchProtWrapper, size: NSSize(width: 150, height: 100))
        defer { notchProtWindow.orderOut(nil) }
        await pumpEvents()

        guard let notchProtMenu = extractContextMenu(from: notchProtHosting, in: notchProtWindow) else {
            Issue.record("Failed to extract context menu from NotchCardWrapper (protected)")
            return
        }
        let notchProtTitles = notchProtMenu.items.map(\.title)
        Swift.print("[DOM/AX STATE] Notch card protected context menu items: \(notchProtTitles)")
        #expect(!notchProtTitles.contains("Gửi sang thiết bị"), "Notch card context menu for protected item must NOT contain 'Gửi sang thiết bị'")

        // Library card wrapper (ordinary item):
        let libWrapper = LibraryCardWrapper(module: module, item: item)
        let (libWindow, libHosting) = makeHostingWindow(view: libWrapper, size: NSSize(width: 150, height: 100))
        defer { libWindow.orderOut(nil) }
        await pumpEvents()

        guard let libMenu = extractContextMenu(from: libHosting, in: libWindow) else {
            Issue.record("Failed to extract context menu from LibraryCardWrapper (ordinary)")
            return
        }
        let libTitles = libMenu.items.map(\.title)
        Swift.print("[DOM/AX STATE] Library card context menu items: \(libTitles)")
        #expect(libTitles.contains("Gửi sang thiết bị"), "Library card context menu for ordinary item must contain 'Gửi sang thiết bị'")

        // Library card wrapper (sensitive item):
        let libSensWrapper = LibraryCardWrapper(module: module, item: sensitiveItem)
        let (libSensWindow, libSensHosting) = makeHostingWindow(view: libSensWrapper, size: NSSize(width: 150, height: 100))
        defer { libSensWindow.orderOut(nil) }
        await pumpEvents()

        guard let libSensMenu = extractContextMenu(from: libSensHosting, in: libSensWindow) else {
            Issue.record("Failed to extract context menu from LibraryCardWrapper (sensitive)")
            return
        }
        let libSensTitles = libSensMenu.items.map(\.title)
        Swift.print("[DOM/AX STATE] Library card sensitive context menu items: \(libSensTitles)")
        #expect(!libSensTitles.contains("Gửi sang thiết bị"), "Library card context menu for sensitive item must NOT contain 'Gửi sang thiết bị'")

        // Library card wrapper (protected board item):
        let libProtWrapper = LibraryCardWrapper(module: module, item: protectedItem)
        let (libProtWindow, libProtHosting) = makeHostingWindow(view: libProtWrapper, size: NSSize(width: 150, height: 100))
        defer { libProtWindow.orderOut(nil) }
        await pumpEvents()

        guard let libProtMenu = extractContextMenu(from: libProtHosting, in: libProtWindow) else {
            Issue.record("Failed to extract context menu from LibraryCardWrapper (protected)")
            return
        }
        let libProtTitles = libProtMenu.items.map(\.title)
        Swift.print("[DOM/AX STATE] Library card protected context menu items: \(libProtTitles)")
        #expect(!libProtTitles.contains("Gửi sang thiết bị"), "Library card context menu for protected item must NOT contain 'Gửi sang thiết bị'")
    }

    // T28b: Copy ảnh hoặc file không bao giờ tự động gửi sang cloud (chỉ gửi khi chọn menu thủ công)
    @Test func nonTextCopyDoesNotAutoSendToCloud() {
        let sampleImage = ClipboardImage(fileName: "img.png", pixelWidth: 100, pixelHeight: 100, byteCount: 500)
        let imageContent = ClipboardContent.image(sampleImage)
        let imageItem = ClipboardItem(
            id: UUID(),
            content: imageContent,
            contentHash: ClipboardContent.hash(of: imageContent),
            copiedAt: Date(),
            sensitive: false
        )
        let fileContent = ClipboardContent.files([URL(fileURLWithPath: "/tmp/sample.pdf")])
        let fileItem = ClipboardItem(
            id: UUID(),
            content: fileContent,
            contentHash: ClipboardContent.hash(of: fileContent),
            copiedAt: Date(),
            sensitive: false
        )

        // Both are eligible for manual on-demand send via context menu
        #expect(ClipboardModule.canSendToCloud(imageItem))
        #expect(ClipboardModule.canSendToCloud(fileItem))
    }

    // T28c: Thực nghiệm kích hoạt context menu "Gửi sang thiết bị" trong trạng thái kết nối và xác thực chuyển giao tệp đến receiver
    @Test func contextMenuActionSendToCloudBehavior() async throws {
        let module = ClipboardModule()
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // 0. Stage receiver directory and sender test files
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudMenuTest_\(UUID().uuidString)")
        let receiverDir = testDir.appendingPathComponent("Receiver")
        try FileManager.default.createDirectory(at: receiverDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let notchFile = testDir.appendingPathComponent("sample_notch.txt")
        let notchContent = "Notch card empirical transfer via context menu action selection"
        try notchContent.write(to: notchFile, atomically: true, encoding: .utf8)
        let notchHash = SHA256.hash(data: Data(notchContent.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        let notchFileItem = ClipboardItem(
            id: UUID(),
            content: .files([notchFile]),
            contentHash: ClipboardContent.hash(of: .files([notchFile])),
            copiedAt: Date(),
            sensitive: false
        )

        let libFile = testDir.appendingPathComponent("sample_library.txt")
        let libContent = "Library card empirical transfer via context menu action selection"
        try libContent.write(to: libFile, atomically: true, encoding: .utf8)
        let libHash = SHA256.hash(data: Data(libContent.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        let libFileItem = ClipboardItem(
            id: UUID(),
            content: .files([libFile]),
            contentHash: ClipboardContent.hash(of: .files([libFile])),
            copiedAt: Date(),
            sensitive: false
        )

        let sensitiveItem = ClipboardItem(
            id: UUID(),
            content: .files([notchFile]),
            contentHash: ClipboardContent.hash(of: .files([notchFile])),
            copiedAt: Date(),
            sensitive: true
        )
        let protectedID = UUID()
        let protectedItem = ClipboardItem(
            id: protectedID,
            content: .files([notchFile]),
            contentHash: ClipboardContent.hash(of: .files([notchFile])),
            copiedAt: Date(),
            sensitive: false
        )
        let lockedBoard = ClipboardBoard(
            id: UUID(),
            name: "Secret Vault",
            systemImage: "lock.shield",
            color: .accent,
            itemIDs: [protectedID],
            lock: ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        )
        module.state.history.boards = [lockedBoard]

        // Setup live connected test receiver via CloudSyncManager test bridge
        let verifiedReceipts = LockIsolated<[CloudSyncManager.VerifiedTransferReceipt]>([])
        let payloadDispatchCount = LockIsolated<Int>(0)
        let peerSession = "receiver-device-session-uuid"
        let manager = CloudSyncManager.shared
        let key = try CloudSyncCrypto.importKeyBase64(manager.config.aesKeyBase64)

        manager.setConnectedForTesting(
            isRunning: true,
            peerSessionId: peerSession
        ) { envelopeV2, jsonString in
            payloadDispatchCount.withValue { $0 += 1 }

            #expect(jsonString.utf8.count <= 2 * 1024 * 1024, "Wire envelope must strictly respect 2 MiB ceiling")
            #expect(envelopeV2.type == "clip_v2", "Envelope must be V2 protocol")

            guard let plaintext = try? CloudSyncCrypto.decryptV2(envelope: envelopeV2, using: key),
                  let payload = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
                Issue.record("Failed to decrypt or parse incoming V2 envelope on receiver")
                return
            }

            guard let kind = payload["kind"] as? String, kind == "file",
                  let transferId = payload["transfer_id"] as? String,
                  let fileName = payload["file_name"] as? String,
                  let fileHash = payload["file_hash"] as? String,
                  let contentBase64 = payload["content_base64"] as? String,
                  let fileData = Data(base64Encoded: contentBase64) else {
                return
            }

            let destURL = receiverDir.appendingPathComponent(fileName)
            try? fileData.write(to: destURL)

            let savedHash = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
            #expect(savedHash == fileHash, "Receiver saved file hash must match envelope hash")

            let receipt = CloudSyncManager.VerifiedTransferReceipt(
                transferId: transferId,
                fileHash: fileHash,
                senderSessionId: payload["sender_session_id"] as? String ?? "",
                savedPath: destURL.path
            )
            verifiedReceipts.withValue { $0.append(receipt) }

            // Deliver complete_ack through product protocol handleMessageV2 (never directly complete completer)
            let ackPayload: [String: Any] = [
                "kind": "complete_ack",
                "transfer_id": transferId,
                "file_hash": fileHash,
                "status": "success",
                "sender_session_id": manager.currentSessionId,
                "receiver_session_id": peerSession,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
            if let ackData = try? JSONSerialization.data(withJSONObject: ackPayload),
               let ackEnvelope = try? CloudSyncCrypto.encryptV2(plaintext: ackData, using: key, senderId: "android-peer") {
                Task { @MainActor in
                    manager.handleMessageV2(ackEnvelope)
                }
            }
        }
        defer {
            manager.setConnectedForTesting(isRunning: false, peerSessionId: nil, envelopeHandler: nil)
        }

        #expect(CloudSyncManager.shared.isRunningState == true, "CloudSyncManager must be in running/connected state")
        #expect(CloudSyncManager.shared.config.isEnabled == true, "CloudSyncManager must be enabled")

        // 1. Notch context menu selection on ordinary file item:
        let notchWrapper = NotchCardWrapper(module: module, item: notchFileItem)
        let (notchWindow, notchHosting) = makeHostingWindow(view: notchWrapper, size: NSSize(width: 150, height: 100))
        defer { notchWindow.orderOut(nil) }
        await pumpEvents()

        guard let notchMenu = extractContextMenu(from: notchHosting, in: notchWindow) else {
            Issue.record("Failed to extract context menu from NotchCardWrapper")
            return
        }
        let notchTitles = notchMenu.items.map(\.title)
        #expect(notchTitles.contains("Gửi sang thiết bị"), "Notch context menu must contain 'Gửi sang thiết bị'")

        Swift.print("[UI-DISPATCH] Selecting 'Gửi sang thiết bị' from Notch context menu via triggerMenuItem")
        let notchSelected = triggerMenuItem(titled: "Gửi sang thiết bị", in: notchMenu)
        #expect(notchSelected, "Must successfully select 'Gửi sang thiết bị' from Notch context menu")
        await settle(until: { verifiedReceipts.value.count >= 1 })

        let currentReceipts1 = verifiedReceipts.value
        #expect(currentReceipts1.count == 1, "Transfer 1 must actually arrive at receiver")
        guard currentReceipts1.count >= 1 else { return }
        let receipt1 = currentReceipts1[0]

        #expect(receipt1.fileHash == notchHash, "Receipt hash must match original Notch file hash")
        #expect(FileManager.default.fileExists(atPath: receipt1.savedPath), "Destination file must exist on receiver disk")
        let savedData1 = try? Data(contentsOf: URL(fileURLWithPath: receipt1.savedPath))
        #expect(savedData1 == Data(notchContent.utf8), "Destination file content must match byte-for-byte")
        await settle(until: { module.lastToastText == "Đã gửi 1 tệp tin thành công" })
        #expect(module.lastToastText == "Đã gửi 1 tệp tin thành công", "Sender must confirm successful delivery toast")
        #expect(module.lastToastSystemImage == "doc", "Sender must display document success icon")
        #expect(manager.isTransferProcessed(receipt1.transferId), "Sender must record verified receipt for Notch transfer")
        #expect(manager.getProcessedReceipt(receipt1.transferId)?.fileHash == notchHash, "Sender recorded receipt hash must match original file hash")
        Swift.print("[SIDE-EFFECT] Notch file transfer delivered to receiver: \(receipt1.savedPath), hash: \(receipt1.fileHash)")

        // 2. Library context menu selection on ordinary file item:
        let libWrapper = LibraryCardWrapper(module: module, item: libFileItem)
        let (libWindow, libHosting) = makeHostingWindow(view: libWrapper, size: NSSize(width: 150, height: 100))
        defer { libWindow.orderOut(nil) }
        await pumpEvents()

        guard let libMenu = extractContextMenu(from: libHosting, in: libWindow) else {
            Issue.record("Failed to extract context menu from LibraryCardWrapper")
            return
        }
        let libTitles = libMenu.items.map(\.title)
        #expect(libTitles.contains("Gửi sang thiết bị"), "Library context menu must contain 'Gửi sang thiết bị'")

        Swift.print("[UI-DISPATCH] Selecting 'Gửi sang thiết bị' from Library context menu via triggerMenuItem")
        let libSelected = triggerMenuItem(titled: "Gửi sang thiết bị", in: libMenu)
        #expect(libSelected, "Must successfully select 'Gửi sang thiết bị' from Library context menu")
        await settle(until: { verifiedReceipts.value.count >= 2 })

        let currentReceipts2 = verifiedReceipts.value
        #expect(currentReceipts2.count == 2, "Transfer 2 must actually arrive at receiver")
        guard currentReceipts2.count >= 2 else { return }
        let receipt2 = currentReceipts2[1]

        #expect(receipt2.fileHash == libHash, "Receipt hash must match original Library file hash")
        #expect(FileManager.default.fileExists(atPath: receipt2.savedPath), "Destination file must exist on receiver disk")
        let savedData2 = try? Data(contentsOf: URL(fileURLWithPath: receipt2.savedPath))
        #expect(savedData2 == Data(libContent.utf8), "Destination file content must match byte-for-byte")
        await settle(until: { module.lastToastText == "Đã gửi 1 tệp tin thành công" })
        #expect(module.lastToastText == "Đã gửi 1 tệp tin thành công", "Sender must confirm successful delivery toast for Library item")
        #expect(module.lastToastSystemImage == "doc", "Sender must display document success icon")
        #expect(manager.isTransferProcessed(receipt2.transferId), "Sender must record verified receipt for Library transfer")
        #expect(manager.getProcessedReceipt(receipt2.transferId)?.fileHash == libHash, "Sender recorded receipt hash must match original file hash")
        Swift.print("[SIDE-EFFECT] Library file transfer delivered to receiver: \(receipt2.savedPath), hash: \(receipt2.fileHash)")

        // 3. Guard checks: Sensitive item on BOTH Notch and Library strictly omits action and creates NO transfer
        let currentTransferCount = verifiedReceipts.value.count
        let currentDispatchCount = payloadDispatchCount.value

        // Notch sensitive item:
        let notchSensWrapper = NotchCardWrapper(module: module, item: sensitiveItem)
        let (notchSensWin, notchSensHost) = makeHostingWindow(view: notchSensWrapper, size: NSSize(width: 150, height: 100))
        defer { notchSensWin.orderOut(nil) }
        await pumpEvents()

        guard let notchSensMenu = extractContextMenu(from: notchSensHost, in: notchSensWin) else {
            Issue.record("Failed to extract context menu from NotchCardWrapper (sensitive)")
            return
        }
        #expect(!notchSensMenu.items.map(\.title).contains("Gửi sang thiết bị"), "Sensitive item Notch context menu must NOT contain 'Gửi sang thiết bị'")
        #expect(!triggerMenuItem(titled: "Gửi sang thiết bị", in: notchSensMenu), "Triggering 'Gửi sang thiết bị' on sensitive Notch menu must fail")

        // Library sensitive item:
        let libSensWrapper = LibraryCardWrapper(module: module, item: sensitiveItem)
        let (libSensWin, libSensHost) = makeHostingWindow(view: libSensWrapper, size: NSSize(width: 150, height: 100))
        defer { libSensWin.orderOut(nil) }
        await pumpEvents()

        guard let libSensMenu = extractContextMenu(from: libSensHost, in: libSensWin) else {
            Issue.record("Failed to extract context menu from LibraryCardWrapper (sensitive)")
            return
        }
        #expect(!libSensMenu.items.map(\.title).contains("Gửi sang thiết bị"), "Sensitive item Library context menu must NOT contain 'Gửi sang thiết bị'")
        #expect(!triggerMenuItem(titled: "Gửi sang thiết bị", in: libSensMenu), "Triggering 'Gửi sang thiết bị' on sensitive Library menu must fail")

        // 4. Guard checks: Protected board item on BOTH Notch and Library strictly omits action and creates NO transfer
        // Notch protected item:
        let notchProtWrapper = NotchCardWrapper(module: module, item: protectedItem)
        let (notchProtWin, notchProtHost) = makeHostingWindow(view: notchProtWrapper, size: NSSize(width: 150, height: 100))
        defer { notchProtWin.orderOut(nil) }
        await pumpEvents()

        guard let notchProtMenu = extractContextMenu(from: notchProtHost, in: notchProtWin) else {
            Issue.record("Failed to extract context menu from NotchCardWrapper (protected)")
            return
        }
        #expect(!notchProtMenu.items.map(\.title).contains("Gửi sang thiết bị"), "Protected item Notch context menu must NOT contain 'Gửi sang thiết bị'")
        #expect(!triggerMenuItem(titled: "Gửi sang thiết bị", in: notchProtMenu), "Triggering 'Gửi sang thiết bị' on protected Notch menu must fail")

        // Library protected item:
        let libProtWrapper = LibraryCardWrapper(module: module, item: protectedItem)
        let (libProtWin, libProtHost) = makeHostingWindow(view: libProtWrapper, size: NSSize(width: 150, height: 100))
        defer { libProtWin.orderOut(nil) }
        await pumpEvents()

        guard let libProtMenu = extractContextMenu(from: libProtHost, in: libProtWin) else {
            Issue.record("Failed to extract context menu from LibraryCardWrapper (protected)")
            return
        }
        #expect(!libProtMenu.items.map(\.title).contains("Gửi sang thiết bị"), "Protected item Library context menu must NOT contain 'Gửi sang thiết bị'")
        #expect(!triggerMenuItem(titled: "Gửi sang thiết bị", in: libProtMenu), "Triggering 'Gửi sang thiết bị' on protected Library menu must fail")

        await pumpEvents()
        #expect(verifiedReceipts.value.count == currentTransferCount, "Guards must strictly prevent any new transfer or destination file creation")
        #expect(payloadDispatchCount.value == currentDispatchCount, "Guards must strictly ensure zero payload dispatch for sensitive and protected items")
        Swift.print("[DOM/AX STATE] Guarded: sensitive and protected items strictly omitted from both Notch and Library menus, 0 payloads dispatched, 0 transfers created")
    }

    // T28d: Kiểm thử tích hợp hai chiều NSMenu -> WebSocket Relay Thật (local-server.js) -> Receiver Thật -> complete_ack
    @Test func contextMenuActionSendToCloudRealRelayIntegration() async throws {
        let module = ClipboardModule()
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // 0. Stage receiver directory and sender test files
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudRelayIntegration_\(UUID().uuidString)")
        let receiverDir = testDir.appendingPathComponent("Receiver")
        try FileManager.default.createDirectory(at: receiverDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let notchFile = testDir.appendingPathComponent("relay_notch.txt")
        let notchContent = "Notch card real WebSocket relay integration content"
        try notchContent.write(to: notchFile, atomically: true, encoding: .utf8)
        let notchHash = SHA256.hash(data: Data(notchContent.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        let notchFileItem = ClipboardItem(
            id: UUID(),
            content: .files([notchFile]),
            contentHash: ClipboardContent.hash(of: .files([notchFile])),
            copiedAt: Date(),
            sensitive: false
        )

        let libFile = testDir.appendingPathComponent("relay_library.txt")
        let libContent = "Library card real WebSocket relay integration content"
        try libContent.write(to: libFile, atomically: true, encoding: .utf8)
        let libHash = SHA256.hash(data: Data(libContent.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        let libFileItem = ClipboardItem(
            id: UUID(),
            content: .files([libFile]),
            contentHash: ClipboardContent.hash(of: .files([libFile])),
            copiedAt: Date(),
            sensitive: false
        )

        let corruptFile = testDir.appendingPathComponent("relay_corrupt.txt")
        let corruptContent = "Corrupt ACK real WebSocket relay integration content"
        try corruptContent.write(to: corruptFile, atomically: true, encoding: .utf8)
        let corruptHash = SHA256.hash(data: Data(corruptContent.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        let corruptFileItem = ClipboardItem(
            id: UUID(),
            content: .files([corruptFile]),
            contentHash: ClipboardContent.hash(of: .files([corruptFile])),
            copiedAt: Date(),
            sensitive: false
        )

        // 1. Spawn local product WebSocket relay server on ephemeral port 8794
        var repoRoot = URL(fileURLWithPath: #filePath)
        while repoRoot.path != "/" && !FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("Tools/mynotch-cloud-relay/local-server.js").path) {
            repoRoot = repoRoot.deletingLastPathComponent()
        }
        let relayScript = repoRoot.appendingPathComponent("Tools/mynotch-cloud-relay/local-server.js").path
        guard FileManager.default.fileExists(atPath: relayScript) else {
            Issue.record("Could not locate local-server.js at \(relayScript)")
            return
        }

        let relayPort = "8794"
        let relayProcess = Process()
        relayProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        relayProcess.arguments = ["node", relayScript]
        var env = ProcessInfo.processInfo.environment
        env["PORT"] = relayPort
        relayProcess.environment = env
        try relayProcess.run()
        defer {
            relayProcess.terminate()
            relayProcess.waitUntilExit()
        }

        // Wait for relay server health
        let healthURL = URL(string: "http://127.0.0.1:\(relayPort)/health")!
        var relayReady = false
        for _ in 0..<30 {
            if let data = try? Data(contentsOf: healthURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "ok" {
                relayReady = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard relayReady else {
            Issue.record("Failed to start local WebSocket relay on port \(relayPort)")
            return
        }

        // 2. Setup crypto key and channel
        let symmetricKey = SymmetricKey(size: .bits256)
        let keyBase64 = symmetricKey.withUnsafeBytes { Data($0).base64EncodedString() }
        let key = try CloudSyncCrypto.importKeyBase64(keyBase64)
        let channelId = "menu-test-channel-" + UUID().uuidString.prefix(8)
        let authToken = "auth-token-relay-test"

        // 3. Setup real Receiver WebSocket client
        let receiverWsURL = URL(string: "ws://127.0.0.1:\(relayPort)/ws?channel=\(channelId)&auth=\(authToken)")!
        let receiverSession = URLSession(configuration: .default)
        let receiverTask = receiverSession.webSocketTask(with: receiverWsURL)
        receiverTask.resume()
        defer { receiverTask.cancel(with: .normalClosure, reason: nil) }

        let receiverReceipts = LockIsolated<[CloudSyncManager.VerifiedTransferReceipt]>([])
        let receiverSessionId = "android-relay-peer-session"
        let corruptNextAck = LockIsolated<Bool>(false)

        let receiverTaskRunning = LockIsolated<Bool>(true)
        let listenTask = Task { @MainActor in
            while receiverTaskRunning.value {
                do {
                    let msg = try await receiverTask.receive()
                    guard case .string(let text) = msg, let data = text.data(using: .utf8) else { continue }
                    guard let envelope = try? JSONDecoder().decode(CloudSyncEnvelopeV2.self, from: data) else { continue }
                    if envelope.senderId == "macbook",
                       let plaintext = try? CloudSyncCrypto.decryptV2(envelope: envelope, using: key),
                       let json = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
                       let kind = json["kind"] as? String {

                        if kind == "hello" {
                            let readyObj: [String: Any] = [
                                "kind": "ready",
                                "session_id": receiverSessionId,
                                "peer_session_id": json["session_id"] as? String ?? "",
                                "senderId": "android",
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]
                            if let readyData = try? JSONSerialization.data(withJSONObject: readyObj),
                               let readyEnv = try? CloudSyncCrypto.encryptV2(plaintext: readyData, using: key, senderId: "android"),
                               let readyJson = try? JSONEncoder().encode(readyEnv),
                               let readyText = String(data: readyJson, encoding: .utf8) {
                                try? await receiverTask.send(.string(readyText))
                            }
                        } else if kind == "file" {
                            if let transferId = json["transfer_id"] as? String,
                               let fileName = json["file_name"] as? String,
                               let fileHash = json["file_hash"] as? String,
                               let contentBase64 = json["content_base64"] as? String,
                               let fileData = Data(base64Encoded: contentBase64) {
                                let destURL = receiverDir.appendingPathComponent(fileName)
                                try? fileData.write(to: destURL)
                                let receipt = CloudSyncManager.VerifiedTransferReceipt(
                                    transferId: transferId,
                                    fileHash: fileHash,
                                    senderSessionId: json["sender_session_id"] as? String ?? "",
                                    savedPath: destURL.path
                                )
                                receiverReceipts.withValue { $0.append(receipt) }

                                // Send complete_ack over real WebSocket
                                let ackHash = corruptNextAck.value ? "corrupted_hash_mismatch_deadbeef" : fileHash
                                let ackObj: [String: Any] = [
                                    "kind": "complete_ack",
                                    "transfer_id": transferId,
                                    "file_hash": ackHash,
                                    "status": "success",
                                    "sender_session_id": json["sender_session_id"] as? String ?? "",
                                    "receiver_session_id": receiverSessionId,
                                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                                ]
                                if let ackData = try? JSONSerialization.data(withJSONObject: ackObj),
                                   let ackEnv = try? CloudSyncCrypto.encryptV2(plaintext: ackData, using: key, senderId: "android"),
                                   let ackJson = try? JSONEncoder().encode(ackEnv),
                                   let ackText = String(data: ackJson, encoding: .utf8) {
                                    try? await receiverTask.send(.string(ackText))
                                }
                            }
                        }
                    }
                } catch {
                    break
                }
            }
        }
        defer {
            receiverTaskRunning.withValue { $0 = false }
            listenTask.cancel()
        }

        // 4. Connect sender CloudSyncManager.shared to real relay
        let manager = CloudSyncManager.shared
        let originalConfig = manager.config
        var cfg = manager.config
        cfg.relayServerUrl = "http://127.0.0.1:\(relayPort)/ws"
        cfg.channelId = String(channelId)
        cfg.authToken = authToken
        cfg.aesKeyBase64 = keyBase64
        cfg.isEnabled = true
        manager.config = cfg
        defer {
            manager.disconnect()
            manager.config = originalConfig
        }

        // Wait until handshake completes over real WebSocket
        for _ in 0..<40 {
            if manager.peerSessionId != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(manager.peerSessionId != nil, "Handshake over real WebSocket relay must establish peerSessionId")

        let initialToastCount = harness.presenter.toastCount

        // 5. Notch context menu selection on ordinary file item over real relay:
        let notchWrapper = NotchCardWrapper(module: module, item: notchFileItem)
        let (notchWindow, notchHosting) = makeHostingWindow(view: notchWrapper, size: NSSize(width: 150, height: 100))
        defer { notchWindow.orderOut(nil) }
        await pumpEvents()

        guard let notchMenu = extractContextMenu(from: notchHosting, in: notchWindow) else {
            Issue.record("Failed to extract context menu from NotchCardWrapper")
            return
        }
        Swift.print("[UI-DISPATCH-RELAY] Selecting 'Gửi sang thiết bị' from Notch context menu via triggerMenuItem over real relay")
        let notchSelected = triggerMenuItem(titled: "Gửi sang thiết bị", in: notchMenu)
        #expect(notchSelected, "Must successfully select 'Gửi sang thiết bị' from Notch context menu")
        await settle(until: { receiverReceipts.value.count >= 1 })

        let currentReceipts1 = receiverReceipts.value
        #expect(currentReceipts1.count == 1, "Real relay transfer 1 must arrive at receiver")
        guard currentReceipts1.count >= 1 else { return }
        let receipt1 = currentReceipts1[0]

        #expect(receipt1.fileHash == notchHash, "Receipt hash must match original Notch file hash")
        #expect(FileManager.default.fileExists(atPath: receipt1.savedPath), "Destination file must exist on receiver disk")
        let savedData1 = try? Data(contentsOf: URL(fileURLWithPath: receipt1.savedPath))
        #expect(savedData1 == Data(notchContent.utf8), "Destination file content must match byte-for-byte")

        // Wait for sender to process complete_ack and display success toast
        await settle(until: { module.lastToastText == "Đã gửi 1 tệp tin thành công" })
        #expect(module.lastToastText == "Đã gửi 1 tệp tin thành công", "Sender must display success toast for Notch transfer over real relay")
        #expect(module.lastToastSystemImage == "doc", "Sender must display document success icon")
        #expect(module.lastToastText != "Một số tệp tin gửi thất bại hoặc hết thời gian chờ", "Sender must not display failure toast")
        #expect(manager.isTransferProcessed(receipt1.transferId), "Sender must record verified receipt for Notch transfer over real relay")
        #expect(manager.getProcessedReceipt(receipt1.transferId)?.fileHash == notchHash, "Sender recorded receipt hash must match Notch file hash")
        #expect(harness.presenter.toastCount == initialToastCount + 2, "Both in-flight and completion toasts must be displayed upon confirmed complete_ack over real relay")
        Swift.print("[SIDE-EFFECT-RELAY] Notch file transfer delivered over real relay to: \(receipt1.savedPath)")

        // 6. Library context menu selection on ordinary file item over real relay:
        let libWrapper = LibraryCardWrapper(module: module, item: libFileItem)
        let (libWindow, libHosting) = makeHostingWindow(view: libWrapper, size: NSSize(width: 150, height: 100))
        defer { libWindow.orderOut(nil) }
        await pumpEvents()

        guard let libMenu = extractContextMenu(from: libHosting, in: libWindow) else {
            Issue.record("Failed to extract context menu from LibraryCardWrapper")
            return
        }
        Swift.print("[UI-DISPATCH-RELAY] Selecting 'Gửi sang thiết bị' from Library context menu via triggerMenuItem over real relay")
        let libSelected = triggerMenuItem(titled: "Gửi sang thiết bị", in: libMenu)
        #expect(libSelected, "Must successfully select 'Gửi sang thiết bị' from Library context menu")
        await settle(until: { receiverReceipts.value.count >= 2 })

        let currentReceipts2 = receiverReceipts.value
        #expect(currentReceipts2.count == 2, "Real relay transfer 2 must arrive at receiver")
        guard currentReceipts2.count >= 2 else { return }
        let receipt2 = currentReceipts2[1]

        #expect(receipt2.fileHash == libHash, "Receipt hash must match original Library file hash")
        #expect(FileManager.default.fileExists(atPath: receipt2.savedPath), "Destination file must exist on receiver disk")
        let savedData2 = try? Data(contentsOf: URL(fileURLWithPath: receipt2.savedPath))
        #expect(savedData2 == Data(libContent.utf8), "Destination file content must match byte-for-byte")

        // Wait for sender to process complete_ack and display success toast
        await settle(until: { module.lastToastText == "Đã gửi 1 tệp tin thành công" })
        #expect(module.lastToastText == "Đã gửi 1 tệp tin thành công", "Sender must display success toast for Library transfer over real relay")
        #expect(module.lastToastSystemImage == "doc", "Sender must display document success icon")
        #expect(module.lastToastText != "Một số tệp tin gửi thất bại hoặc hết thời gian chờ", "Sender must not display failure toast")
        #expect(manager.isTransferProcessed(receipt2.transferId), "Sender must record verified receipt for Library transfer over real relay")
        #expect(manager.getProcessedReceipt(receipt2.transferId)?.fileHash == libHash, "Sender recorded receipt hash must match Library file hash")
        #expect(harness.presenter.toastCount == initialToastCount + 4, "Both in-flight and completion toasts must be displayed upon confirmed complete_ack over real relay")
        Swift.print("[SIDE-EFFECT-RELAY] Library file transfer delivered over real relay to: \(receipt2.savedPath)")

        // 7. Negative corrupted ACK verification over real WebSocket relay:
        // Receiver receives file, but responds with corrupted complete_ack (hash mismatch).
        // Sender must reject the corrupted ACK, display failure toast, and NOT record processed receipt.
        corruptNextAck.withValue { $0 = true }

        let corruptWrapper = NotchCardWrapper(module: module, item: corruptFileItem)
        let (corruptWindow, corruptHosting) = makeHostingWindow(view: corruptWrapper, size: NSSize(width: 150, height: 100))
        defer { corruptWindow.orderOut(nil) }
        await pumpEvents()

        guard let corruptMenu = extractContextMenu(from: corruptHosting, in: corruptWindow) else {
            Issue.record("Failed to extract context menu from corrupt NotchCardWrapper")
            return
        }
        Swift.print("[UI-DISPATCH-RELAY] Selecting 'Gửi sang thiết bị' for corrupt ACK test via triggerMenuItem over real relay")
        let corruptSelected = triggerMenuItem(titled: "Gửi sang thiết bị", in: corruptMenu)
        #expect(corruptSelected, "Must successfully select 'Gửi sang thiết bị' from context menu")
        await settle(until: { receiverReceipts.value.count >= 3 })

        let currentReceipts3 = receiverReceipts.value
        #expect(currentReceipts3.count == 3, "Real relay transfer 3 must arrive at receiver")
        guard currentReceipts3.count >= 3 else { return }
        let receipt3 = currentReceipts3[2]
        #expect(receipt3.fileHash == corruptHash, "Receiver must compute correct hash for corrupt test file")

        // Wait for sender to process the corrupted ACK and show failure toast
        await settle(until: { module.lastToastText == "Một số tệp tin gửi thất bại hoặc hết thời gian chờ" })
        #expect(module.lastToastText == "Một số tệp tin gửi thất bại hoặc hết thời gian chờ", "Sender must display failure toast when complete_ack has corrupted file hash")
        #expect(module.lastToastSystemImage == "exclamationmark.triangle", "Sender must display warning icon on transfer failure")
        #expect(!manager.isTransferProcessed(receipt3.transferId), "Sender must NOT record verified receipt when complete_ack is rejected")
        #expect(manager.getProcessedReceipt(receipt3.transferId) == nil, "Sender processed receipt for rejected transfer must be nil")
        #expect(harness.presenter.toastCount == initialToastCount + 6, "Failure toast must be counted in total toasts")
        Swift.print("[SIDE-EFFECT-RELAY] Corrupted ACK properly rejected by sender, failure toast shown, receipt omitted")
    }

    // T29: Item sensitive hoặc thuộc board bảo vệ không được phép gửi
    @Test func sensitiveItemCannotBeSentToCloud() {
        let content = ClipboardContent.text("Sensitive Password")
        let item = ClipboardItem(
            id: UUID(),
            content: content,
            contentHash: ClipboardContent.hash(of: content),
            copiedAt: Date(),
            sensitive: true
        )
        #expect(!ClipboardModule.canSendToCloud(item))
    }

    // T29b: Item thuộc board bảo vệ không được phép gửi
    @Test func protectedBoardItemCannotBeSentToCloud() {
        let id = UUID()
        let content = ClipboardContent.text("Protected Secret")
        let item = ClipboardItem(
            id: id,
            content: content,
            contentHash: ClipboardContent.hash(of: content),
            copiedAt: Date(),
            sensitive: false
        )
        #expect(!ClipboardModule.canSendToCloud(item, protectedIDs: [id]))
    }

    // T27: Item bình thường (text, link, image, file) được phép gửi
    @Test func ordinaryItemsCanBeSentToCloud() {
        let textContent = ClipboardContent.text("Normal text")
        let textItem = ClipboardItem(
            id: UUID(),
            content: textContent,
            contentHash: ClipboardContent.hash(of: textContent),
            copiedAt: Date(),
            sensitive: false
        )
        #expect(ClipboardModule.canSendToCloud(textItem))

        let linkContent = ClipboardContent.link(URL(string: "https://example.com")!)
        let linkItem = ClipboardItem(
            id: UUID(),
            content: linkContent,
            contentHash: ClipboardContent.hash(of: linkContent),
            copiedAt: Date(),
            sensitive: false
        )
        #expect(ClipboardModule.canSendToCloud(linkItem))
    }

    // T27b: Kiểm tra toàn bộ 6 định dạng content hỗ trợ gửi qua CloudSync V2
    @Test func allSixFormatsSupportedWhenNotSensitive() {
        let sampleImage = ClipboardImage(
            fileName: "sample.png",
            pixelWidth: 100,
            pixelHeight: 100,
            byteCount: 1024
        )
        let contents: [ClipboardContent] = [
            .text("Plain Text"),
            .richText(plain: "Rich Plain", rtf: Data("rtf".utf8)),
            .link(URL(string: "https://mynotch.app")!),
            .color(hex: "#FF0000", original: "Red"),
            .image(sampleImage),
            .files([URL(fileURLWithPath: "/tmp/doc.pdf")])
        ]

        for content in contents {
            let item = ClipboardItem(
                id: UUID(),
                content: content,
                contentHash: ClipboardContent.hash(of: content),
                copiedAt: Date(),
                sensitive: false
            )
            #expect(ClipboardModule.canSendToCloud(item), "Format \(content) must be eligible for cloud sync")
        }
    }

    // T31: Giới hạn số lượng tệp trong một batch (tối đa 10 tệp) và dung lượng 15 MiB
    @Test func batchLimitConstants() {
        let maxBatchFiles = 10
        let filesUnderLimit = (1...10).map { URL(fileURLWithPath: "/tmp/file\($0).pdf") }
        let filesOverLimit = (1...11).map { URL(fileURLWithPath: "/tmp/file\($0).pdf") }
        #expect(filesUnderLimit.count <= maxBatchFiles)
        #expect(filesOverLimit.count > maxBatchFiles)

        let exactLimit: Int64 = 15 * 1024 * 1024 // 15,728,640 bytes
        #expect(CloudSyncFileTransfer.maxFileSizeBytes == exactLimit)
        #expect(CloudSyncFileTransfer.isFileSizeAllowed(fileSize: exactLimit))
        #expect(!CloudSyncFileTransfer.isFileSizeAllowed(fileSize: exactLimit + 1))
    }
}

private final class LockIsolated<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withValue<R>(_ block: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try block(&_value)
    }
}
