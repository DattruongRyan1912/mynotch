import AppKit
import Foundation

extension ClipboardModule {

    /// Determines whether a clipboard item can be manually sent to the paired mobile device.
    static func canSendToCloud(_ item: ClipboardItem, protectedIDs: Set<UUID> = []) -> Bool {
        guard !item.isSensitive else { return false }
        guard !protectedIDs.contains(item.id) else { return false }
        switch item.content {
        case .text, .richText, .link, .color, .image, .files:
            return true
        }
    }

    /// Instance check checking current history's protected boards
    func canSendToCloud(_ item: ClipboardItem) -> Bool {
        Self.canSendToCloud(item, protectedIDs: state.history.protectedItemIDs)
    }

    /// Manually sends a selected clipboard item to the paired device via CloudSync V2.
    func sendToCloud(item: ClipboardItem) {
        guard canSendToCloud(item) else {
            showToast("Mục nhạy cảm hoặc bị khoá không thể gửi", systemImage: "lock.shield")
            return
        }

        guard CloudSyncManager.shared.isRunningState, CloudSyncManager.shared.config.isEnabled else {
            showToast("Cloud Sync chưa được bật hoặc chưa kết nối", systemImage: "bolt.slash")
            return
        }

        switch item.content {
        case .text(let text):
            CloudSyncManager.shared.sendClipV2(text: text, sourceApp: item.sourceAppName)
            showToast("Đã gửi văn bản sang thiết bị", systemImage: "arrow.triangle.2.circlepath")

        case .richText(let plain, _):
            CloudSyncManager.shared.sendClipV2(text: plain, sourceApp: item.sourceAppName)
            showToast("Đã gửi văn bản sang thiết bị", systemImage: "arrow.triangle.2.circlepath")

        case .link(let url):
            CloudSyncManager.shared.sendLinkV2(url: url, sourceApp: item.sourceAppName)
            showToast("Đã gửi link sang thiết bị", systemImage: "link")

        case .color(let hex, let original):
            let colorText = original ?? hex
            CloudSyncManager.shared.sendClipV2(text: colorText, sourceApp: item.sourceAppName)
            showToast("Đã gửi màu sắc sang thiết bị", systemImage: "paintpalette")

        case .image(let image):
            if let source = previewImageSource(of: item) {
                let data: Data?
                switch source {
                case .file(let url):
                    data = try? Data(contentsOf: url)
                case .memory(let memoryData):
                    data = memoryData
                }
                if let data {
                    showToast("Đang gửi ảnh sang thiết bị...", systemImage: "arrow.up.circle")
                    Task { @MainActor in
                        let task = CloudSyncManager.shared.sendImageV2(
                            imageData: data,
                            fileName: image.fileName,
                            width: image.pixelWidth,
                            height: image.pixelHeight,
                            sourceApp: item.sourceAppName
                        )
                        let success = await task.value
                        if success {
                            showToast("Đã gửi ảnh thành công", systemImage: "photo")
                        } else {
                            showToast("Gửi ảnh thất bại hoặc hết thời gian chờ phản hồi", systemImage: "exclamationmark.triangle")
                        }
                    }
                } else {
                    showToast("Không đọc được dữ liệu ảnh", systemImage: "exclamationmark.triangle")
                }
            }

        case .files(let urls):
            let regularFiles = urls.filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
            }
            guard !regularFiles.isEmpty else {
                showToast("Không có tệp tin hợp lệ để gửi", systemImage: "exclamationmark.triangle")
                return
            }

            // Reject batch exceeding 10 files
            guard regularFiles.count <= 10 else {
                showToast("Số lượng tệp tin (\(regularFiles.count)) vượt quá giới hạn tối đa 10 tệp", systemImage: "exclamationmark.triangle")
                return
            }

            // Verify total batch size does not exceed 15 MiB
            var totalBatchSize: Int64 = 0
            for url in regularFiles {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? NSNumber else {
                    showToast("Không thể đọc dung lượng tệp \(url.lastPathComponent)", systemImage: "exclamationmark.triangle")
                    return
                }
                totalBatchSize += size.int64Value
            }
            guard totalBatchSize <= CloudSyncFileTransfer.maxFileSizeBytes else {
                showToast("Tổng dung lượng batch (\(totalBatchSize / 1024 / 1024) MiB) vượt quá 15 MiB", systemImage: "exclamationmark.triangle")
                return
            }

            showToast("Đang gửi \(regularFiles.count) tệp tin sang thiết bị...", systemImage: "arrow.up.circle")
            Task { @MainActor in
                var allSucceeded = true
                for fileURL in regularFiles {
                    let task = CloudSyncManager.shared.sendFileV2(fileURL: fileURL, sourceApp: item.sourceAppName)
                    let success = await task.value
                    if !success {
                        allSucceeded = false
                    }
                }
                if allSucceeded {
                    showToast("Đã gửi \(regularFiles.count) tệp tin thành công", systemImage: "doc")
                } else {
                    showToast("Một số tệp tin gửi thất bại hoặc hết thời gian chờ", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }
}
