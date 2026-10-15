import CryptoKit
import Foundation
import MyNotchCore

/// How a board is to be locked.
enum ClipboardLockSetup {
    case password(String)
    case touchID
}

/// What opens a locked board.
enum ClipboardUnlockCredential {
    case password(String)
    case touchID
}

/// Locked boards. A board that has a lock keeps its items sealed in a vault file (AES-GCM, the key under a password or in the
/// Keychain behind Touch ID); while it is locked they are not in memory, not in `history.json`, and their images are not on disk.
/// Opening it puts them back in memory (and the images back on disk, since every card, paste and drag reads a file) until it is
/// closed again, by the user or by the idle time, the screen lock, sleep or the notch closing.
extension ClipboardModule {
    /// The boards that have a lock, open or not. What an agent is told never to read from, and what a backup leaves out.
    var protectedBoardIDs: Set<UUID> {
        Set(state.history.boards.filter(\.isProtected).map(\.id))
    }

    private var hasOpenBoards: Bool {
        state.history.boards.contains { $0.lock?.isUnlocked == true }
    }

    // MARK: Start and stop

    /// Marks the boards that have a vault file as locked, and takes out of `history` any item of theirs that a crash left in the
    /// clear (the vault is written before the history is, so it holds them). Returns those items for their images to be deleted.
    func startVault(_ context: ModuleContext, history: inout ClipboardHistory) -> [ClipboardItem] {
        let vault = ClipboardVault(files: ClipboardVaultFiles(directory: context.storage.directory.appending(path: "vault", directoryHint: .isDirectory)))
        self.vault = vault
        var removed: [ClipboardItem] = []
        for summary in vault.files.summaries() {
            guard history.boards.contains(where: { $0.id == summary.boardID }) else { continue }
            removed += history.lockBoard(id: summary.boardID, method: summary.method)
            if let index = history.boards.firstIndex(where: { $0.id == summary.boardID }) {
                history.boards[index].lock?.itemCount = summary.itemCount
            }
        }
        for source in lockTriggers.sources {
            for name in source.names {
                let token = source.center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    // The system posts these on the main thread; anything else is moved there.
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.relockAllBoards() }
                    } else {
                        DispatchQueue.main.async { self?.relockAllBoards() }
                    }
                }
                vault.observers.append((source.center, token))
            }
        }
        return removed
    }

    /// Seals and closes every open board and stops listening. Called before the module lets go of its store.
    func stopVault() {
        guard let vault else { return }
        relockAllBoards()
        vault.cancelTimers()
        for (center, token) in vault.observers { center.removeObserver(token) }
        vault.observers = []
        self.vault = nil
    }

    // MARK: Locking

    /// Locks the board: its items go into a vault file, and out of the history, memory and disk. Throws `ClipboardVaultError`, and
    /// then nothing has changed. A password takes a good part of a second to turn into a key, which happens off the main actor.
    func lockBoard(_ id: UUID, setup: ClipboardLockSetup) async throws {
        guard let vault, let store else { throw ClipboardVaultError.moduleStopped }
        guard let board = state.history.boards.first(where: { $0.id == id }) else { throw ClipboardVaultError.boardNotFound }
        guard !board.isProtected else { throw ClipboardVaultError.alreadyLocked }
        guard vault.busy.insert(id).inserted else { throw ClipboardVaultError.busy }
        defer { vault.busy.remove(id) }

        let method: ClipboardLockMethod
        let key: SymmetricKey
        var envelope: ClipboardVaultEnvelope
        switch setup {
        case .password(let password):
            guard ClipboardVaultPolicy.isAcceptable(password) else { throw ClipboardVaultError.passwordTooShort }
            let wrapping = try await ClipboardVaultCrypto.wrapNewKeyInBackground(password: password, boardID: id, using: keyDerivation)
            method = .password
            key = wrapping.key
            envelope = ClipboardVaultEnvelope(
                boardID: id, method: .password, itemCount: 0, derivation: wrapping.derivation, wrappedKey: wrapping.wrappedKey
            )
        case .touchID:
            method = .touchID
            key = ClipboardVaultCrypto.randomKey()
            try await storeTouchIDKey(key, for: board)
            envelope = ClipboardVaultEnvelope(boardID: id, method: .touchID, itemCount: 0)
        }
        var committed = false
        defer {
            // A key that no vault holds is removed again.
            if !committed, method == .touchID { try? keychain.remove(for: id) }
        }

        // Seal what the board holds; if it changed while that ran, once more.
        for _ in 0..<4 {
            guard self.store === store else { throw ClipboardVaultError.moduleStopped }
            let pinned = state.history.items(of: id)
            // An item whose image file is gone could never be shown or pasted; it is not worth keeping.
            let usable = pinned.filter { hasImageFile($0, in: store) }
            let sealed = try await ClipboardVaultSealer.seal(items: usable, imagesDirectory: store.imagesDirectory, key: key, boardID: id)
            guard self.store === store else { throw ClipboardVaultError.moduleStopped }
            guard let now = state.history.boards.first(where: { $0.id == id }) else { throw ClipboardVaultError.boardNotFound }
            guard !now.isProtected else { throw ClipboardVaultError.alreadyLocked }
            guard state.history.items(of: id) == pinned else { continue }

            envelope.itemCount = usable.count
            try vault.files.prepare()
            vault.files.moveAside(for: id)
            try ClipboardVaultFile(envelope: envelope, sealed: sealed).write(to: vault.files.url(for: id))
            // From here on the vault is the truth: the items are taken out of memory and off the disk at once, in one step.
            var removed: [ClipboardItem] = []
            update { history in
                removed = history.lockBoard(id: id, method: method)
                if let index = history.boards.firstIndex(where: { $0.id == id }) { history.boards[index].lock?.itemCount = usable.count }
                return removed
            }
            committed = true
            released(removed)
            await store.flush()
            return
        }
        throw ClipboardVaultError.busy
    }

    /// Makes a key for Touch ID and proves it can be read back before any data is sealed with it: a key that cannot be read again
    /// would be data nobody can open.
    private func storeTouchIDKey(_ key: SymmetricKey, for board: ClipboardBoard) async throws {
        let bytes = key.withUnsafeBytes { Data($0) }
        try keychain.store(bytes, for: board.id)
        do {
            let authentication = try await authenticator.authenticate(reason: "Xác nhận để khoá bảng “\(board.name)” bằng Touch ID")
            guard try keychain.load(for: board.id, authentication: authentication) == bytes else { throw ClipboardVaultError.keyMissing }
        } catch {
            try? keychain.remove(for: board.id)
            throw error
        }
    }

    // MARK: Unlocking

    /// Opens the board: the items are decrypted into memory, their images are written back to disk, and the board closes again by
    /// itself after the idle time. Throws `ClipboardVaultError` and then the board is as it was, locked.
    func unlockBoard(_ id: UUID, credential: ClipboardUnlockCredential) async throws {
        guard let vault, let store else { throw ClipboardVaultError.moduleStopped }
        guard let board = state.history.boards.first(where: { $0.id == id }) else { throw ClipboardVaultError.boardNotFound }
        guard let lock = board.lock else { throw ClipboardVaultError.notLocked }
        guard lock.isUnlocked == false else { return }
        guard vault.busy.insert(id).inserted else { throw ClipboardVaultError.busy }
        defer { vault.busy.remove(id) }

        let source: ClipboardVaultSealer.KeySource
        switch (credential, lock.method) {
        case (.password(let password), .password):
            source = .password(password)
        case (.touchID, .touchID):
            let authentication = try await authenticator.authenticate(reason: "Mở khoá bảng “\(board.name)”")
            source = .key(try keychain.load(for: id, authentication: authentication))
        default:
            throw ClipboardVaultError.wrongMethod
        }
        let opened = try await ClipboardVaultSealer.open(
            at: vault.files.url(for: id), boardID: id, source: source, policy: keyDerivation, imagesDirectory: store.imagesDirectory
        )
        // The module may have stopped or the board been deleted while the key was made.
        guard self.store === store, self.vault === vault, state.history.boards.first(where: { $0.id == id })?.isLocked == true else {
            for url in opened.createdImages { try? FileManager.default.removeItem(at: url) }
            throw ClipboardVaultError.moduleStopped
        }
        update { history in
            history.unlockBoard(id: id, with: opened.items)
            return []
        }
        vault.keys[id] = opened.key
        vault.envelopes[id] = opened.envelope
        vault.sealedItems[id] = opened.items
        noteVaultActivity()
    }

    /// Takes the lock off an open board for good: its items stay where they are, pinned, and are written like any other. The
    /// vault file (and the Touch ID key) go once the items are safely in the history file.
    func removeLock(from id: UUID) async throws {
        guard let vault, let store else { throw ClipboardVaultError.moduleStopped }
        guard let board = state.history.boards.first(where: { $0.id == id }) else { throw ClipboardVaultError.boardNotFound }
        guard let lock = board.lock else { throw ClipboardVaultError.notLocked }
        guard lock.isUnlocked else { throw ClipboardVaultError.stillLocked }
        guard vault.busy.insert(id).inserted else { throw ClipboardVaultError.busy }
        defer { vault.busy.remove(id) }

        update { history in
            history.removeLock(id: id)
            return []
        }
        // The items are in `history.json` before the only sealed copy is removed; a crash in between leaves both, and the vault wins.
        await store.flush()
        guard self.store === store else { throw ClipboardVaultError.moduleStopped }
        try vault.files.remove(for: id)
        if lock.method == .touchID { try? keychain.remove(for: id) }
        vault.forget(id)
    }

    // MARK: Closing

    /// Seals what changed and takes the items out of memory and the images off the disk. false when it could not be sealed, and
    /// then the board stays open rather than lose what it holds.
    @discardableResult
    func relockBoard(_ id: UUID) -> Bool {
        guard let vault, store != nil, let method = state.history.boards.first(where: { $0.id == id })?.lock,
              method.isUnlocked else { return false }
        guard sealIfChanged(id) else { return false }
        let count = vault.envelopes[id]?.itemCount
        var removed: [ClipboardItem] = []
        update { history in
            removed = history.lockBoard(id: id, method: method.method)
            if let count, let index = history.boards.firstIndex(where: { $0.id == id }) { history.boards[index].lock?.itemCount = count }
            return removed
        }
        vault.forget(id)
        released(removed)
        if !hasOpenBoards { vault.cancelTimers() }
        return true
    }

    /// Closes every open board: the idle time, the screen lock, sleep, the module stopping.
    func relockAllBoards() {
        for board in state.history.boards where board.lock?.isUnlocked == true { relockBoard(board.id) }
    }

    /// The notch closed (or the tab was left): closes the boards when Settings says so.
    func notchDidClose() {
        guard let context, let keys, context.settings.value(keys.boardLockOnNotchClose) else { return }
        relockAllBoards()
    }

    /// The user did something with an open board: the idle time starts again. Does nothing while none is open.
    func noteVaultActivity() {
        guard let vault, let context, let keys, hasOpenBoards else { return }
        vault.idleTimer?.cancel()
        let minutes = context.settings.value(keys.boardLockIdleMinutes)
        vault.idleTimer = context.scheduler.schedule(after: .seconds(minutes * 60)) { [weak self] in self?.relockAllBoards() }
    }

    /// `update` calls this after every change: a change to an open board is sealed a second later, so the vault is never far behind.
    func vaultHistoryChanged() {
        guard let vault, vault.resealTimer == nil, let context, hasOpenBoards else { return }
        vault.resealTimer = context.scheduler.schedule(after: .seconds(1)) { [weak self] in
            self?.vault?.resealTimer = nil
            self?.sealOpenBoards()
        }
    }

    /// Seals every open board that has changed since its vault file was written. false when one could not be.
    @discardableResult
    func sealOpenBoards() -> Bool {
        var all = true
        for board in state.history.boards where board.lock?.isUnlocked == true {
            if !sealIfChanged(board.id) { all = false }
        }
        return all
    }

    private func sealIfChanged(_ id: UUID) -> Bool {
        guard let vault, let store, let key = vault.keys[id], var envelope = vault.envelopes[id] else { return false }
        let current = state.history.items(of: id)
        if current == vault.sealedItems[id] { return true }
        let usable = current.filter { hasImageFile($0, in: store) }
        do {
            let sealed = try ClipboardVaultSealer.sealNow(items: usable, imagesDirectory: store.imagesDirectory, key: key, boardID: id)
            envelope.itemCount = usable.count
            try ClipboardVaultFile(envelope: envelope, sealed: sealed).write(to: vault.files.url(for: id))
            vault.envelopes[id] = envelope
            vault.sealedItems[id] = current
            return true
        } catch {
            // Never what was being sealed, only that it failed.
            let nsError = error as NSError
            context?.logger.error("Sealing a locked board failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))")
            return false
        }
    }

    /// What happens to the rest of the module once items have left memory: they leave the copy stack, which would otherwise still
    /// hold them, and the thumbnails of their images are forgotten.
    private func released(_ items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        updateStack { $0.removeEntries { ids.contains($0.item.id) } }
        thumbnails.removeAll()
        library?.thumbnails.removeAll()
        panel?.thumbnails.removeAll()
        state.forgetSearchText()
    }

    // MARK: Deleting

    /// "Xoá bảng" for a board that has a lock, which stays possible when the password is forgotten: the board, its vault file, its
    /// Touch ID key and (if it is open) its items go, and no copy of them is kept.
    func deleteProtectedBoard(_ board: ClipboardBoard) {
        guard let lock = board.lock else { return }
        var removed: [ClipboardItem] = []
        update { history in
            removed = history.deleteProtectedBoard(id: board.id)
            return removed
        }
        try? vault?.files.remove(for: board.id)
        if lock.method == .touchID { try? keychain.remove(for: board.id) }
        vault?.forget(board.id)
        released(removed)
        if !hasOpenBoards { vault?.cancelTimers() }
    }
}
