import Foundation
import Observation

/// What the form that locks a board, the prompt that opens one and the two confirmations decide, apart from drawing: whether a
/// password can be used, what to say when it cannot, and what a failure looks like. It holds the password only while the form
/// is up and empties it as soon as the work is done.
@Observable
final class ClipboardBoardLockModel {
    enum Status: Equatable {
        case idle
        case working
        case failed(String)
    }

    /// What the user is about to be asked to confirm.
    enum Confirmation: Equatable {
        /// "Xoá board": the board and its encrypted data go, with no way back.
        case deleteData
        /// "Gỡ khoá": the items stay, no longer encrypted.
        case removeLock
    }

    /// The words under the forms, in one place so tests can hold them to the brief.
    static let noRecoveryWarning = "Không có cách khôi phục: nếu quên mật khẩu, nội dung của board này mất vĩnh viễn. Bạn vẫn xoá được board (dữ liệu đã mã hoá bị xoá theo)."
    static let touchIDNote = "Touch ID: khoá nằm trong Keychain của máy này, mở bằng Touch ID hoặc mật khẩu máy. Không đưa vào sao lưu được."
    /// Where the build has no Keychain access group, Touch ID is not offered and this says why.
    static let touchIDUnavailableNote = "Touch ID cần bản MyNotch có hồ sơ ký; hiện dùng mật khẩu."
    /// Locking does not erase what was written before it.
    static let priorCopiesNote = "Bản chép cũ của nội dung này có thể còn trong Time Machine hoặc ảnh chụp ổ đĩa tạo trước khi khoá."
    static let tooShort = "Mật khẩu cần ít nhất \(ClipboardVaultPolicy.minimumPasswordLength) ký tự."
    static let differ = "Hai mật khẩu chưa giống nhau."

    let boardName: String
    /// How the board is opened; nil while it has no lock yet.
    let method: ClipboardLockMethod?
    /// What the board holds, as the locked board shows it.
    let itemCount: Int
    /// Whether this build can keep a key behind Touch ID (see `ClipboardModule.touchIDAvailable`).
    let touchIDAvailable: Bool

    var password = "" {
        didSet { clearFailure() }
    }
    var confirmation = "" {
        didSet { clearFailure() }
    }
    private(set) var status = Status.idle
    private(set) var confirming: Confirmation?

    /// Called once a lock, an unlock, a deletion or a removal has been done.
    @ObservationIgnored var onDone: (() -> Void)?
    @ObservationIgnored private let lock: (ClipboardLockSetup) async throws -> Void
    @ObservationIgnored private let unlock: (ClipboardUnlockCredential) async throws -> Void
    @ObservationIgnored private let deleteData: () -> Void
    @ObservationIgnored private let removeLock: () async throws -> Void

    init(
        boardName: String, method: ClipboardLockMethod?, itemCount: Int, touchIDAvailable: Bool,
        lock: @escaping (ClipboardLockSetup) async throws -> Void,
        unlock: @escaping (ClipboardUnlockCredential) async throws -> Void,
        deleteData: @escaping () -> Void,
        removeLock: @escaping () async throws -> Void
    ) {
        self.boardName = boardName
        self.method = method
        self.itemCount = itemCount
        self.touchIDAvailable = touchIDAvailable
        self.lock = lock
        self.unlock = unlock
        self.deleteData = deleteData
        self.removeLock = removeLock
    }

    var isWorking: Bool { status == .working }

    /// The lock form offers Touch ID only where it can work.
    var showsTouchID: Bool { touchIDAvailable }

    /// What the form says of Touch ID: how it works, or why it is not offered.
    var touchIDNote: String { touchIDAvailable ? Self.touchIDNote : Self.touchIDUnavailableNote }

    /// Why the password cannot be used yet, once there is something to complain about; nil while it is fine or still empty.
    var problem: String? {
        if !password.isEmpty, !ClipboardVaultPolicy.isAcceptable(password) { return Self.tooShort }
        if !confirmation.isEmpty, confirmation != password { return Self.differ }
        return nil
    }

    var canLockWithPassword: Bool {
        !isWorking && ClipboardVaultPolicy.isAcceptable(password) && password == confirmation
    }

    var canUnlockWithPassword: Bool {
        !isWorking && !password.isEmpty
    }

    var failureMessage: String? {
        if case .failed(let message) = status { message } else { nil }
    }

    // MARK: Actions

    func lockWithPassword() async {
        guard canLockWithPassword else { return }
        await run { try await self.lock(.password(self.password)) }
    }

    func lockWithTouchID() async {
        guard !isWorking, touchIDAvailable else { return }
        await run { try await self.lock(.touchID) }
    }

    func unlockWithPassword() async {
        guard canUnlockWithPassword else { return }
        await run { try await self.unlock(.password(self.password)) }
    }

    func unlockWithTouchID() async {
        guard !isWorking else { return }
        await run { try await self.unlock(.touchID) }
    }

    func ask(_ confirmation: Confirmation) {
        guard !isWorking else { return }
        confirming = confirmation
        status = .idle
    }

    func cancelConfirmation() {
        confirming = nil
    }

    /// The user said yes to what `confirming` asked.
    func confirm() async {
        guard let confirming, !isWorking else { return }
        switch confirming {
        case .deleteData:
            self.confirming = nil
            deleteData()
            finish()
        case .removeLock:
            await run { try await self.removeLock() }
        }
    }

    // MARK: Private

    private func run(_ work: () async throws -> Void) async {
        status = .working
        do {
            try await work()
            finish()
        } catch ClipboardVaultError.cancelled {
            // The user dismissed Touch ID: nothing went wrong.
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func finish() {
        password = ""
        confirmation = ""
        confirming = nil
        status = .idle
        onDone?()
    }

    private func clearFailure() {
        if case .failed = status { status = .idle }
    }
}

extension ClipboardModule {
    /// The model behind the form or prompt of one board.
    func lockModel(for board: ClipboardBoard) -> ClipboardBoardLockModel {
        let id = board.id
        return ClipboardBoardLockModel(
            boardName: board.name, method: board.lock?.method, itemCount: board.shownItemCount, touchIDAvailable: touchIDAvailable,
            lock: { [weak self] setup in
                guard let self else { throw ClipboardVaultError.moduleStopped }
                try await self.lockBoard(id, setup: setup)
            },
            unlock: { [weak self] credential in
                guard let self else { throw ClipboardVaultError.moduleStopped }
                try await self.unlockBoard(id, credential: credential)
            },
            deleteData: { [weak self] in self?.deleteBoard(id) },
            removeLock: { [weak self] in
                guard let self else { throw ClipboardVaultError.moduleStopped }
                try await self.removeLock(from: id)
            }
        )
    }
}

/// What a notch tab or a library window may be asked to show over the cards, for one board.
enum ClipboardVaultPrompt: Identifiable, Equatable {
    case lock(UUID)
    case removeLock(UUID)
    case deleteData(UUID)

    var id: String {
        switch self {
        case .lock(let id): "lock-\(id)"
        case .removeLock(let id): "removeLock-\(id)"
        case .deleteData(let id): "deleteData-\(id)"
        }
    }

    var boardID: UUID {
        switch self {
        case .lock(let id), .removeLock(let id), .deleteData(let id): id
        }
    }
}
