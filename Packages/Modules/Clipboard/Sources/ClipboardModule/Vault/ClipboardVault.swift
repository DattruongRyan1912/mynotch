import CryptoKit
import Foundation
import MyNotchCore

/// What the module keeps of the locked boards while it runs: the keys of the ones that are open (only in memory, gone when the
/// board closes), what each vault file holds right now, and the timers and listeners that close them again.
final class ClipboardVault {
    let files: ClipboardVaultFiles
    /// The board key of each open board.
    var keys: [UUID: SymmetricKey] = [:]
    /// The header of each open board's vault file, whose key wrapping a later seal reuses.
    var envelopes: [UUID: ClipboardVaultEnvelope] = [:]
    /// What the vault file holds of each open board, to tell when the board has changed and has to be sealed again.
    var sealedItems: [UUID: [ClipboardItem]] = [:]
    /// Boards a lock or unlock is working on, so two of them never run on one board.
    var busy: Set<UUID> = []
    /// Closes the open boards after the idle time; restarted by what the user does with them.
    var idleTimer: ScheduledAction?
    /// Seals the changes of the open boards a moment after they are made; nil when none is pending.
    var resealTimer: ScheduledAction?
    var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    /// Wrong passwords in a row for each board, and until when it takes no more tries; in memory, and forgotten by a right one.
    var failures: [UUID: (count: Int, until: Date?)] = [:]
    /// Raised by every lock trigger, so an unlock that was under way when one came does not open the board after it.
    var lockGeneration = 0
    /// The files of drags of an open board's pictures.
    let dragFiles: ClipboardDragFiles
    /// Removes the drag files that are left after a drag, once it has been over for a moment.
    var dragCleanup: ScheduledAction?

    init(files: ClipboardVaultFiles, dragDirectory: URL) {
        self.files = files
        dragFiles = ClipboardDragFiles(directory: dragDirectory)
    }

    func forget(_ boardID: UUID) {
        keys[boardID] = nil
        envelopes[boardID] = nil
        sealedItems[boardID] = nil
    }

    func cancelTimers() {
        dragCleanup?.cancel()
        dragCleanup = nil
        idleTimer?.cancel()
        idleTimer = nil
        resealTimer?.cancel()
        resealTimer = nil
    }
}
