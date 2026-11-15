import Foundation
import Observation

/// What Settings can ask of the module. A restore is read first (`planRestore`, which writes nothing) and the offer it returns
/// is what the user chooses by.
struct ClipboardBackupActions {
    var export: (ClipboardBackupOptions, URL, @escaping @Sendable (Double) -> Void) async throws -> ClipboardBackupExportSummary
    var planRestore: (URL, @escaping @Sendable (Double) -> Void) async throws -> ClipboardRestoreOffer
    /// How many text items a backup of the scope would hold that were saved before MyNotch tracked which copies are secrets,
    /// so the sheet can say it cannot tell whether they are.
    var legacyTextCount: (ClipboardBackupOptions.Scope) -> Int
    /// How many boards have a lock, which the options sheet offers to include.
    var lockedBoardCount: () -> Int = { 0 }
}

/// What the Settings rows show of a backup or restore, and the one task behind it. One thing at a time: a second start while
/// one is working, or while a restore waits for its choice, is ignored.
@Observable
final class ClipboardBackupModel {
    enum Status: Equatable {
        case idle
        case working(title: String, fraction: Double)
        /// A restore has been read and nothing has been done; the user decides.
        case choosing(ClipboardRestorePlanSummary)
        case finished(String)
        case failed(String)
        case cancelled
    }

    private(set) var status = Status.idle
    /// Kept so a test (and `cancel`) can reach the work in progress.
    private(set) var task: Task<Void, Never>?
    @ObservationIgnored private let actions: ClipboardBackupActions?
    /// The restore that waits for the choice.
    @ObservationIgnored private var offer: ClipboardRestoreOffer?

    init(actions: ClipboardBackupActions?) {
        self.actions = actions
    }

    var isAvailable: Bool { actions != nil }

    var isWorking: Bool {
        if case .working = status { true } else { false }
    }

    /// The plan the user is to choose by, while there is one.
    var choosingSummary: ClipboardRestorePlanSummary? {
        if case .choosing(let summary) = status { summary } else { nil }
    }

    /// Working, or waiting for a choice: nothing else may start.
    var isBusy: Bool { isWorking || choosingSummary != nil }

    func legacyTextCount(for scope: ClipboardBackupOptions.Scope) -> Int {
        actions?.legacyTextCount(scope) ?? 0
    }

    func lockedBoardCount() -> Int {
        actions?.lockedBoardCount() ?? 0
    }

    func startExport(_ options: ClipboardBackupOptions, to url: URL) {
        guard let actions, !isBusy else { return }
        run("Đang sao lưu…") { progress in try await actions.export(options, url, progress).text }
    }

    /// Reads the file, which changes nothing, and ends in the choice.
    func startRestore(from url: URL) {
        guard let actions, !isBusy else { return }
        status = .working(title: "Đang đọc tệp…", fraction: 0)
        task = Task { [weak self] in
            do {
                let offer = try await actions.planRestore(url) { fraction in
                    Task { @MainActor in self?.progressChanged(fraction) }
                }
                self?.offer = offer
                self?.status = .choosing(offer.summary)
            } catch is CancellationError {
                self?.status = .cancelled
            } catch {
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    /// The user's answer: do the restore this way.
    func confirmRestore(_ policy: ClipboardRestorePolicy) {
        guard choosingSummary != nil, let offer else { return }
        self.offer = nil
        run("Đang khôi phục…") { progress in try await offer.commit(policy, progress).text }
    }

    /// The user's answer: do not. Nothing was written, so there is nothing to undo.
    func declineRestore() {
        guard choosingSummary != nil else { return }
        offer = nil
        status = .cancelled
    }

    /// Asks the work to stop; its status becomes `cancelled` when it has.
    func cancel() {
        task?.cancel()
    }

    /// Clears a finished, failed or cancelled message. A restore waiting for its choice stays until it is answered.
    func dismiss() {
        if !isBusy { status = .idle }
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
