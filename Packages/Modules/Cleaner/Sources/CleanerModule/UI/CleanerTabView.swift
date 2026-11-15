import AppKit
import Foundation
import NotchUI
import SwiftUI
import UniformTypeIdentifiers

/// Giao diện Notch Tab cho phân hệ Gỡ ứng dụng (CleanerModule) tuân theo chuẩn Linear / Dark Zinc 950.
public struct CleanerTabView: View {
    public static let height: CGFloat = 220
    public static let headerHeight: CGFloat = 18

    @Bindable public var state: CleanerState

    @Environment(\.notch) private var notch
    @Environment(\.notchAccent) private var accent

    public init(state: CleanerState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            contentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchColorScheme()
        .onDrop(of: [.applicationBundle, .application, .fileURL], isTargeted: $state.isTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTokens.secondaryText)

            Text("Gỡ ứng dụng")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                openTrash()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash.circle")
                        .font(.system(size: 11))
                    Text("Thùng rác")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(NotchTokens.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(NotchTokens.fill(0.06))
                )
            }
            .buttonStyle(.plain)
            .help("Mở Thùng rác hệ thống trong Finder")
        }
        .frame(height: Self.headerHeight)
    }

    // MARK: - Content Body
    @ViewBuilder
    private var contentBody: some View {
        switch state.phase {
        case .idle:
            idleDropZone
        case .analyzing(let url):
            analyzingView(url: url)
        case .preview(let info, let residuals, let plan, let isRunning, let selectedIDs):
            previewView(info: info, residuals: residuals, plan: plan, isRunning: isRunning, selectedIDs: selectedIDs)
        case .confirming(let info, let plan, let isRunning):
            confirmingView(info: info, plan: plan, isRunning: isRunning)
        case .deleting(let appName):
            deletingView(appName: appName)
        case .success(let appName, let freedBytes):
            successView(appName: appName, freedBytes: freedBytes)
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Idle Drop Zone
    private var idleDropZone: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(state.isTargeted ? accent : NotchTokens.secondaryText)

            Text("Kéo thả ứng dụng (.app) vào đây")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)

            Text("Quét sạch tệp cấu hình, bộ nhớ đệm và dữ liệu liên quan")
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(state.isTargeted ? accent.opacity(0.08) : NotchTokens.fill(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    state.isTargeted ? accent : NotchTokens.fill(0.12),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
    }

    // MARK: - Analyzing View
    private func analyzingView(url: URL) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)

            Text("Đang phân tích \(url.lastPathComponent)…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)

            Text("Đang quét các tệp dư thừa trong Thư viện (~/Library)")
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview View
    private func previewView(
        info: AppBundleInfo,
        residuals: [Residual],
        plan: DeletionPlan,
        isRunning: Bool,
        selectedIDs: Set<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // App info header
            HStack(spacing: 10) {
                appIconView(for: info.url)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(info.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NotchTokens.primaryText)

                        Text("v\(info.version)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(NotchTokens.secondaryText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(NotchTokens.fill(0.08))
                            )

                        if isRunning {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 5, height: 5)
                                Text("Đang chạy")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.orange)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.12))
                            )
                        }
                    }

                    Text(info.bundleID)
                        .font(.system(size: 10.5).monospaced())
                        .foregroundStyle(NotchTokens.secondaryText)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatBytes(plan.totalBytes))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NotchTokens.primaryText)

                    Text("\(plan.items.count) mục được chọn")
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(NotchTokens.fill(0.04))
            )

            // Residual list with Checkboxes
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    // Package .app row
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(accent)

                        Image(systemName: "app")
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .frame(width: 14)

                        Text(info.displayName + ".app")
                            .font(.system(size: 10.5, weight: .medium).monospaced())
                            .foregroundStyle(NotchTokens.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(formatBytes(info.sizeBytes))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(NotchTokens.secondaryText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(NotchTokens.fill(0.03))
                    )

                    // Residuals list
                    ForEach(residuals) { item in
                        let isSelected = selectedIDs.contains(item.id)
                        Button {
                            state.toggleResidual(id: item.id)
                        } label: {
                            HStack(spacing: 6) {
                                if item.locked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(NotchTokens.secondaryText)
                                } else if item.deniedFDA {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.orange)
                                } else {
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 11))
                                        .foregroundStyle(isSelected ? accent : NotchTokens.secondaryText)
                                }

                                Image(systemName: iconForSubpath(item.url.path))
                                    .font(.system(size: 10))
                                    .foregroundStyle(NotchTokens.secondaryText)
                                    .frame(width: 14)

                                Text(shortenPath(item.url.path))
                                    .font(.system(size: 10.5).monospaced())
                                    .foregroundStyle(item.locked ? NotchTokens.secondaryText : NotchTokens.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if item.locked {
                                    Text("Dùng chung")
                                        .font(.system(size: 9))
                                        .foregroundStyle(NotchTokens.secondaryText)
                                        .padding(.horizontal, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(NotchTokens.fill(0.06))
                                        )
                                }

                                Spacer(minLength: 0)

                                Text(formatBytes(item.bytes))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(NotchTokens.secondaryText)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? accent.opacity(0.06) : NotchTokens.fill(0.02))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(item.locked || item.deniedFDA)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Actions & Warnings
            HStack(spacing: 8) {
                Button("Huỷ") {
                    state.reset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTokens.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(NotchTokens.fill(0.08))
                )

                if isRunning {
                    Text("Đóng ứng dụng để gỡ bỏ")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.orange)
                }

                Spacer()

                Button {
                    state.proceedToConfirmation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Gỡ bỏ ứng dụng")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRunning ? Color.gray.opacity(0.4) : Color.red.opacity(0.85))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Confirming View (2-Step Inline Confirmation)
    private func confirmingView(
        info: AppBundleInfo,
        plan: DeletionPlan,
        isRunning: Bool
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.orange)

            Text("Xác nhận gỡ bỏ \(info.displayName)?")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)

            VStack(spacing: 3) {
                Text("Ứng dụng và \(plan.items.count) mục đã chọn (\(formatBytes(plan.totalBytes))) sẽ được chuyển vào Thùng rác.")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .multilineTextAlignment(.center)

                if isRunning {
                    Text("Ứng dụng đang chạy. Vui lòng đóng ứng dụng trước khi tiếp tục.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                } else {
                    Text("Bạn có thể hoàn tác từ Thùng rác bất cứ lúc nào.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 12) {
                Button("Quay lại") {
                    state.backToPreview()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NotchTokens.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(NotchTokens.fill(0.08))
                )

                Button {
                    state.executeUninstall()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11))
                        Text("Xác nhận gỡ bỏ")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRunning ? Color.gray.opacity(0.4) : Color.red)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Deleting View
    private func deletingView(appName: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)

            Text("Đang chuyển \(appName) vào Thùng rác…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success View
    private func successView(appName: String, freedBytes: Int64) -> some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.green)

            Text("Đã gỡ bỏ \(appName) thành công")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)

            Text("Đã chuyển \(formatBytes(freedBytes)) vào Thùng rác.")
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)

            Spacer()

            HStack(spacing: 10) {
                Button("Mở Thùng rác") {
                    openTrash()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTokens.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(NotchTokens.fill(0.08))
                )

                Button("Hoàn tất") {
                    state.reset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(NotchTokens.fill(0.12))
                )
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View
    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.red)

            Text("Không thể gỡ bỏ ứng dụng")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)

            ScrollView(.vertical, showsIndicators: false) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxHeight: 60)

            Spacer()

            Button("Đóng") {
                state.reset()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NotchTokens.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(NotchTokens.fill(0.1))
            )
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers
    @discardableResult
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Priority 1: Direct drag pasteboard read (synchronous, instant, zero latency)
        if let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let appURL = urls.first(where: { DropRouting.isApplicationURL($0) }) {
            state.analyze(appURL: appURL.standardized)
            return true
        }

        // Priority 2: Asynchronous item provider fallback
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let rawURL = url else { return }
            let appURL = rawURL.standardized
            guard DropRouting.isApplicationURL(appURL) else { return }
            Task { @MainActor in
                state.analyze(appURL: appURL)
            }
        }
        return true
    }

    private func appIconView(for url: URL) -> some View {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return Image(nsImage: icon)
            .resizable()
            .scaledToFit()
    }

    private func iconForSubpath(_ subpath: String) -> String {
        if subpath.hasSuffix(".app") { return "app" }
        if subpath.contains("Caches") { return "archivebox" }
        if subpath.contains("Preferences") { return "gearshape" }
        if subpath.contains("Containers") { return "shippingbox" }
        if subpath.contains("Application Support") { return "folder" }
        return "doc"
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func openTrash() {
        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(trashURL)
        }
    }
}
