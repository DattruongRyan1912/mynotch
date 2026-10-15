import AppKit
import CryptoKit
import Foundation
import MyNotchCore
import UniformTypeIdentifiers

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
/// Opening it puts them back in memory, pictures included, and nowhere else: cards and thumbnails draw from memory, copy and paste
/// write the bytes to the pasteboard, and a file exists only for the length of a drag. It closes again by the user's hand, by the
/// idle time, the screen lock, sleep or the notch closing, and a trigger always closes it, even when the seal fails.
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
        let vault = ClipboardVault(
            files: ClipboardVaultFiles(directory: context.storage.directory.appending(path: "vault", directoryHint: .isDirectory)),
            dragDirectory: context.storage.cachesDirectory.appending(path: "open-drags", directoryHint: .isDirectory)
        )
        self.vault = vault
        // Whatever a drag left behind in an earlier run goes, and nothing of an earlier run's open boards is kept in memory.
        vault.dragFiles.removeAll()
        openImages.removeAll()
        touchIDProbe = nil
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
        vault.dragFiles.removeAll()
        openImages.removeAll()
        self.vault = nil
    }

    // MARK: Touch ID

    /// Whether Touch ID can be offered: the Keychain can keep a key behind it in this build, and this Mac can ask. Looked at once per
    /// run, the first time it is needed, and kept.
    var touchIDAvailable: Bool {
        if let touchIDProbe { return touchIDProbe }
        let answer = keychain.isUsable() && authenticator.canAuthenticate()
        touchIDProbe = answer
        return answer
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
            guard touchIDAvailable else { throw ClipboardVaultError.touchIDUnavailable }
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

    /// Opens the board: the items and their pictures are decrypted into memory (nothing is written to disk), and the board closes
    /// again by itself after the idle time. Throws `ClipboardVaultError` and then the board is as it was, locked. After five wrong
    /// passwords in a row the board takes no more tries for a while, which doubles with each further failure up to ten minutes.
    func unlockBoard(_ id: UUID, credential: ClipboardUnlockCredential) async throws {
        guard let vault, let store else { throw ClipboardVaultError.moduleStopped }
        guard let board = state.history.boards.first(where: { $0.id == id }) else { throw ClipboardVaultError.boardNotFound }
        guard let lock = board.lock else { throw ClipboardVaultError.notLocked }
        guard lock.isUnlocked == false else { return }
        guard vault.busy.insert(id).inserted else { throw ClipboardVaultError.busy }
        defer { vault.busy.remove(id) }
        // A lock trigger that comes while the key is being made must not be followed by the board opening.
        let generation = vault.lockGeneration

        let source: ClipboardVaultSealer.KeySource
        switch (credential, lock.method) {
        case (.password(let password), .password):
            if let until = vault.failures[id]?.until, until > now() {
                throw ClipboardVaultError.tooManyAttempts(retryAfter: Int(until.timeIntervalSince(now()).rounded(.up)))
            }
            source = .password(password)
        case (.touchID, .touchID):
            let authentication = try await authenticator.authenticate(reason: "Mở khoá bảng “\(board.name)”")
            source = .key(try keychain.load(for: id, authentication: authentication))
        default:
            throw ClipboardVaultError.wrongMethod
        }
        let opened: ClipboardVaultSealer.Opened
        do {
            opened = try await ClipboardVaultSealer.open(at: vault.files.url(for: id), boardID: id, source: source, policy: keyDerivation)
        } catch ClipboardVaultError.wrongPassword {
            registerWrongPassword(for: id, in: vault)
            throw ClipboardVaultError.wrongPassword
        }
        // The module may have stopped or the board been deleted while the key was made, or the screen locked.
        guard self.store === store, self.vault === vault, state.history.boards.first(where: { $0.id == id })?.isLocked == true else {
            throw ClipboardVaultError.moduleStopped
        }
        guard vault.lockGeneration == generation else { throw ClipboardVaultError.cancelled }
        vault.failures[id] = nil
        // The pictures are in memory before the items are, so no card ever looks for a file.
        openImages.set(opened.images, for: id)
        update { history in
            history.unlockBoard(id: id, with: opened.items)
            return []
        }
        // A picture of the same words that was copied while the board was closed is the board's now: its file goes.
        store.deleteImages(for: state.history.items(of: id))
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

        // The pictures are about to be ordinary files again, since nothing keeps them in memory once the board is not locked. A
        // picture that cannot be written stops it before anything has changed.
        for (name, data) in openImages.images(of: id) {
            do {
                try store.saveImage(data, fileName: name)
            } catch {
                throw ClipboardVaultError.cannotWrite(error.localizedDescription)
            }
        }
        update { history in
            history.removeLock(id: id)
            return []
        }
        // The items are in `history.json` before the only sealed copy is removed; a crash in between leaves both, and the vault wins.
        await store.flush()
        guard self.store === store else { throw ClipboardVaultError.moduleStopped }
        try vault.files.remove(for: id)
        if lock.method == .touchID { try? keychain.remove(for: id) }
        forgetBoard(id)
    }

    /// A wrong password counts; the fifth in a row and each after it starts a wait that doubles from 30 seconds to ten minutes.
    private func registerWrongPassword(for id: UUID, in vault: ClipboardVault) {
        let count = (vault.failures[id]?.count ?? 0) + 1
        var until: Date?
        if count >= 5 { until = now().addingTimeInterval(min(30 * pow(2, Double(count - 5)), 600)) }
        vault.failures[id] = (count, until)
    }

    // MARK: Closing

    /// Seals what changed, then takes the items and their pictures out of memory. It always closes: when what changed cannot be sealed
    /// the board closes anyway and says so, since the sealed copy on disk is the truth and an open board is what an attacker wants. What
    /// had not been sealed is lost then, which the notice says. false only when there is no open board of that id.
    @discardableResult
    func relockBoard(_ id: UUID) -> Bool {
        guard let vault, store != nil, let board = state.history.boards.first(where: { $0.id == id }), let lock = board.lock,
              lock.isUnlocked else { return false }
        let sealed = sealIfChanged(id)
        let count = vault.envelopes[id]?.itemCount
        var removed: [ClipboardItem] = []
        update { history in
            removed = history.lockBoard(id: id, method: lock.method)
            if let count, let index = history.boards.firstIndex(where: { $0.id == id }) { history.boards[index].lock?.itemCount = count }
            return removed
        }
        forgetBoard(id)
        released(removed)
        if !hasOpenBoards { vault.cancelTimers() }
        if !sealed { announceUnsaved(board.name) }
        return true
    }

    /// Closes every open board: the idle time, the screen lock, sleep, the module stopping. An unlock still under way is told off.
    func relockAllBoards() {
        vault?.lockGeneration += 1
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
        reconcileOpenImages()
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
        guard let vault, store != nil, let key = vault.keys[id], var envelope = vault.envelopes[id] else { return false }
        let current = state.history.items(of: id)
        if current == vault.sealedItems[id] { return true }
        // An item whose picture is not in memory could not be sealed whole; it is left out.
        let usable = current.filter { item in
            if case .image(let image) = item.content { openImages.contains(image.fileName) } else { true }
        }
        do {
            let sealed = try ClipboardVaultSealer.sealNow(items: usable, images: openImages.images(of: id), key: key, boardID: id)
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

    /// An open board that closes, is deleted or loses its lock leaves nothing of itself in memory, and its drag files go.
    private func forgetBoard(_ id: UUID) {
        vault?.forget(id)
        vault?.failures[id] = nil
        openImages.remove(board: id)
        vault?.dragFiles.removeAll()
    }

    /// Says that a board closed without what was changed last: that could not be sealed.
    private func announceUnsaved(_ name: String) {
        let text = "Board “\(name)” đã khoá, nhưng thay đổi mới nhất chưa lưu được nên bị mất; bản mã hoá trước đó được giữ."
        state.vaultNotice = text
        showToast(text, systemImage: "exclamationmark.triangle.fill")
    }

    func dismissVaultNotice() {
        state.vaultNotice = nil
    }

    // MARK: Pictures

    /// After every change: the pictures of the open boards stay in step with their items. A picture whose item left its board is an
    /// ordinary one now, which is a file like any other; one that no item names any more is forgotten.
    func reconcileOpenImages() {
        guard let store, !openImages.isEmpty else { return }
        let protectedIDs = state.history.protectedItemIDs
        for item in state.history.items where !protectedIDs.contains(item.id) {
            guard case .image(let image) = item.content, let data = openImages.data(forFileName: image.fileName) else { continue }
            do {
                try store.saveImage(data, fileName: image.fileName)
            } catch {
                let nsError = error as NSError
                context?.logger.error("Saving a picture that left a locked board failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))")
            }
        }
        for board in state.history.boards where board.lock?.isUnlocked == true {
            let names = Set(state.history.items(of: board.id).compactMap { item -> String? in
                if case .image(let image) = item.content { image.fileName } else { nil }
            })
            openImages.retain(names, for: board.id)
        }
    }

    /// Pictures that were just pinned to an open board move from their files to memory, so nothing of the board is on disk.
    func adoptPictures(_ ids: Set<UUID>, into boardID: UUID) {
        guard let store else { return }
        for item in state.history.items where ids.contains(item.id) {
            guard case .image(let image) = item.content, !openImages.contains(image.fileName),
                  let url = store.imageURL(fileName: image.fileName), let data = try? Data(contentsOf: url) else { continue }
            openImages.add(data, named: image.fileName, to: boardID)
            store.deleteImages(for: [item])
        }
    }

    /// A drag of an open board's picture: the provider makes a file when the drop target asks for one. nil for any other item.
    func openImageDragProvider(for item: ClipboardItem) -> NSItemProvider? {
        guard let vault, let data = openImages.data(for: item) else { return nil }
        let files = vault.dragFiles
        let name = ClipboardDragProvider.imageFileName(copiedAt: item.copiedAt)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            do {
                completion(try files.makeFile(data: data, name: name), false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    /// The drag is over: its file goes once the drop target has had time to read it. Whatever is left is removed when the board
    /// closes, when the module stops and at the next start.
    func dragEnded() {
        guard let vault, let context else { return }
        vault.dragCleanup?.cancel()
        vault.dragCleanup = context.scheduler.schedule(after: Self.dragCleanupDelay) { [weak self] in
            self?.vault?.dragFiles.removeAll()
            self?.vault?.dragCleanup = nil
        }
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
        forgetBoard(board.id)
        released(removed)
        if !hasOpenBoards { vault?.cancelTimers() }
    }
}
