import AppKit
import SwiftUI
// `TranslationSession` isn't Sendable; the task hands this view's session to its own async method, as Apple's samples do.
@preconcurrency import Translation

/// Downloads a language pack through Translation's system sheet, with System Settings as the fallback for when the
/// sheet doesn't show. Re-checks the pack after every attempt, and every 2 s once System Settings was opened.
struct LanguageInstallerView: View {
    let pair: LanguagePair
    let status: () async -> PairStatus
    /// Called when the pack turns out to be installed, so the tab translates again.
    let onStatusChange: () -> Void
    let close: () -> Void

    /// Language & Region's "Translation Languages" list, then the General pane on systems that lack that link.
    private static let systemSettingsURLs = [
        "x-apple.systempreferences:com.apple.Localization-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.general",
    ]

    /// Setting or invalidating it runs the translation task, which shows the download sheet.
    @State private var configuration: TranslationSession.Configuration?
    @State private var current: PairStatus?
    @State private var isDownloading = false
    /// Bumped by every download attempt, so a superseded attempt doesn't report over the current one.
    @State private var attempt = 0
    @State private var failure: String?
    @State private var watchesSystemSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gói ngôn ngữ \(SupportedLanguages.name(of: pair.source)) ↔ \(SupportedLanguages.name(of: pair.target))")
                .font(.headline)
            statusLine
            if let failure {
                Text(failure).font(.callout).foregroundStyle(.secondary)
            }
            Text("Nếu hộp thoại tải không hiện, mở Cài đặt hệ thống › Chung › Ngôn ngữ & Vùng › Ngôn ngữ dịch và tải gói ở đó.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if isDownloading {
                    // The sheet may never show for a menu bar app; asking again cancels the stuck attempt.
                    Button("Thử lại", action: download)
                } else {
                    Button("Tải về", action: download)
                        .disabled(current != .supported)
                }
                Button("Mở cài đặt hệ thống", action: openSystemSettings)
                Spacer()
                Button("Xong", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .translationTask(configuration) { session in
            let started = attempt
            var error: (any Error)?
            do {
                try await session.prepareTranslation()
            } catch let caught {
                error = caught
            }
            guard started == attempt else { return }
            failure = error.map { "Chưa tải được gói: \($0.localizedDescription)" }
            isDownloading = false
            await refresh()
        }
        .task {
            await refresh()
            if current == .supported { download() }
        }
        .task(id: watchesSystemSettings) {
            guard watchesSystemSettings else { return }
            while current != .installed {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return   // the window closed
                }
                await refresh()
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch current {
        case nil:
            Label("Đang kiểm tra…", systemImage: "hourglass")
        case .installed:
            Label("Đã cài, có thể dịch", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .supported:
            if isDownloading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Đang chờ tải…")
                }
            } else {
                Label("Chưa cài", systemImage: "arrow.down.circle")
            }
        case .unsupported:
            Label("Cặp ngôn ngữ này không được hỗ trợ", systemImage: "xmark.circle").foregroundStyle(.red)
        }
    }

    /// Shows the system download sheet; while one attempt waits, invalidating the configuration cancels it and
    /// starts another.
    private func download() {
        attempt += 1
        isDownloading = true
        failure = nil
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: pair.source, target: pair.target)
        } else {
            configuration?.invalidate()
        }
    }

    private func openSystemSettings() {
        for url in Self.systemSettingsURLs.compactMap(URL.init(string:)) {
            if NSWorkspace.shared.open(url) { break }
        }
        watchesSystemSettings = true
    }

    private func refresh() async {
        let latest = await status()
        let installedNow = latest == .installed && current != .installed
        current = latest
        if installedNow { onStatusChange() }
    }
}
