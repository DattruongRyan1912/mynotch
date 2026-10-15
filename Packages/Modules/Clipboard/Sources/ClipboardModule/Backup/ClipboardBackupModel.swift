import Foundation
import Observation

/// What Settings can ask of the running module. The rows get none while the module is stopped.
struct ClipboardBackupActions {
    var export: (ClipboardBackupOptions, URL, @escaping @Sendable (Double) -> Void) async throws -> ClipboardBackupExportSummary
    var restore: (URL, @escaping @Sendable (Double) -> Void) async throws -> ClipboardBackupRestoreSummary
}

/// What the Settings rows show of a backup or restore, and the one task behind it. One at a time: a second start while one
/// is working is ignored.
@Observable
final class ClipboardBackupModel {
    enum Status: Equatable {
        case idle
        case working(title: String, fraction: Double)
        case finished(String)
        case failed(String)
        case cancelled
    }

    private(set) var status = Status.idle
    /// Kept so a test (and `cancel`) can reach the work in progress.
    private(set) var task: Task<Void, Never>?
    @ObservationIgnored private let actions: ClipboardBackupActions?

    init(actions: ClipboardBackupActions?) {
        self.actions = actions
    }

    var isAvailable: Bool { actions != nil }

    var isWorking: Bool {
        if case .working = status { true } else { false }
    }

    func startExport(_ options: ClipboardBackupOptions, to url: URL) {
        guard let actions, !isWorking else { return }
        run("Đang sao lưu…") { progress in try await actions.export(options, url, progress).text }
    }

    func startRestore(from url: URL) {
        guard let actions, !isWorking else { return }
        run("Đang khôi phục…") { progress in try await actions.restore(url, progress).text }
    }

    /// Asks the work to stop; its status becomes `cancelled` when it has.
    func cancel() {
        task?.cancel()
    }

    /// Clears a finished, failed or cancelled message.
    func dismiss() {
        if !isWorking { status = .idle }
    }

    /// From the background, so it arrives in any order; the bar only moves forward.
    func progressChanged(_ fraction: Double) {
        guard case .working(let title, let current) = status, fraction > current else { return }
        status = .working(title: title, fraction: min(fraction, 1))
    }

    private func run(_ title: String, _ work: @escaping (@escaping @Sendable (Double) -> Void) async throws -> String) {
        status = .working(title: title, fraction: 0)
        task = Task { [weak self] in
            do {
                let text = try await work { fraction in
                    Task { @MainActor in self?.progressChanged(fraction) }
                }
                self?.status = .finished(text)
            } catch is CancellationError {
                self?.status = .cancelled
            } catch {
                self?.status = .failed(error.localizedDescription)
            }
        }
    }
}
