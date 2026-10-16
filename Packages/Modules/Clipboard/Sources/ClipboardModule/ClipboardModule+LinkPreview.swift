import Foundation

/// What a card draws of a link's page, when link previews are on and the link may be read.
struct ClipboardLinkPreviewDisplay: Equatable {
    var title: String?
    /// The stored picture's file, nil when there is none.
    var imageURL: URL?

    var isEmpty: Bool { title == nil && imageURL == nil }
}

/// The links waiting to be read and the ones being read, kept by the module. Keyed by the item's content hash, which is the same for the same
/// address, so a link is read once whatever number of cards show it.
final class ClipboardLinkFetches {
    struct Work: Equatable {
        let itemID: UUID
        let hash: String
        let url: URL
        /// Tells this try from another of the same address after the setting went off and on again.
        let token = UUID()
    }

    /// Waiting for one of the places.
    var queue: [Work] = []
    var running: [UUID: Task<Void, Never>] = [:]
    /// Waiting, running, or failed in this run: asked for once, and not again. A read that worked is not here, since the item holds it.
    var known: Set<String> = []
    /// What looks like a secret, worked out once per item.
    let secrets = ClipboardMCPSecretFilter.Cache()
    /// How many reads were started, for tests.
    private(set) var startedCount = 0

    func noteStarted() {
        startedCount += 1
    }

    func cancelAll() {
        running.values.forEach { $0.cancel() }
        running = [:]
        queue = []
        known = []
    }
}

/// The optional link previews: the title and one small picture of a link's page, read when the link first shows in a card. Everything that
/// decides whether a page may be read is here, and it is decided twice: when a card asks, and again when the answer is back, before a
/// byte of it is stored.
extension ClipboardModule {
    /// How many pages are read at the same time: opening the library shows dozens of cards at once.
    static let linkFetchLimit = 3

    /// How long a link's card has to stay on screen before its page is read, so a card that is only scrolled past reads nothing.
    static let defaultLinkPreviewDwell: Duration = .milliseconds(400)

    /// The address of a link item that may be read now; nil when it may not: the setting is off or the module stopped, it is not a link
    /// the guard allows (a private address, credentials), it looks like a link that is used once (a login, a verification, an invitation, a
    /// signed address: a request for it could use it up), it is a secret (marked by the app that copied it, or looking like one), or it
    /// is in a board that has a lock.
    func previewableLinkURL(of item: ClipboardItem) -> URL? {
        guard let context, let keys, store != nil, context.settings.value(keys.linkPreviews), case .link(let url) = item.content,
              ClipboardLinkGuard.allows(url), !ClipboardLinkGuard.looksSingleUse(url), !item.isSensitive, !linkPreviews.secrets.hides(item),
              !state.history.boards.contains(where: { $0.isProtected && $0.itemIDs.contains(item.id) }) else { return nil }
        return url
    }

    /// What a card, row or preview draws for the link: nil when it is not one that may be read (so it looks as it always did), otherwise
    /// what has been read so far, which is nothing until the first read is done.
    func linkPreviewDisplay(for item: ClipboardItem) -> ClipboardLinkPreviewDisplay? {
        guard previewableLinkURL(of: item) != nil else { return nil }
        let imageURL = item.linkPreview?.hasImage == true ? item.linkPreviewFileName.flatMap { store?.linkPreviewURL(fileName: $0) } : nil
        return ClipboardLinkPreviewDisplay(title: item.linkPreview?.title, imageURL: imageURL)
    }

    /// The link of `item` has shown in a card: reads its page, once, unless it may not be read or has been (or has failed in this run).
    /// Nothing happens at start-up or in bulk: only cards that are shown ask.
    func requestLinkPreview(for item: ClipboardItem) {
        guard let current = currentItem(item.id), current.linkPreview == nil, let url = previewableLinkURL(of: current),
              !linkPreviews.known.contains(current.contentHash) else { return }
        linkPreviews.known.insert(current.contentHash)
        linkPreviews.queue.append(ClipboardLinkFetches.Work(itemID: current.id, hash: current.contentHash, url: url))
        startLinkFetches()
    }

    /// Stops what is on its way and forgets what was waiting: the setting went off, or the module stopped.
    func cancelLinkFetches() {
        linkPreviews.cancelAll()
    }

    /// After a change of the history: the pictures that items held before and hold no more (the item was deleted or pruned, its words were
    /// edited, it went into a board that has a lock) are removed.
    func deleteStaleLinkPreviews(of before: Set<String>) {
        // The verdicts of items that are gone are not kept for ever.
        if linkPreviews.secrets.verdictCount > state.history.items.count + 256 {
            linkPreviews.secrets.keepOnly(Set(state.history.items.map(\.id)))
        }
        guard !before.isEmpty, let store else { return }
        let stale = before.subtracting(state.history.linkPreviewFileNames)
        if !stale.isEmpty { store.deleteLinkPreviewImages(named: stale) }
    }

    // MARK: Reading

    private func currentItem(_ id: UUID) -> ClipboardItem? {
        state.history.items.first { $0.id == id }
    }

    /// Whether `work` is still worth doing: its item is there with the same address, has nothing read yet, and may still be read.
    private func isStillWanted(_ work: ClipboardLinkFetches.Work) -> Bool {
        guard let current = currentItem(work.itemID), current.contentHash == work.hash, current.linkPreview == nil else { return false }
        return previewableLinkURL(of: current) == work.url
    }

    private func startLinkFetches() {
        while linkPreviews.running.count < Self.linkFetchLimit, !linkPreviews.queue.isEmpty {
            let work = linkPreviews.queue.removeFirst()
            guard isStillWanted(work) else {
                linkPreviews.known.remove(work.hash)
                continue
            }
            linkPreviews.noteStarted()
            let fetcher = linkFetcher
            let startedWith = store
            linkPreviews.running[work.token] = Task { [weak self] in
                let outcome = await fetcher.fetch(work.url)
                self?.finishLinkFetch(work, outcome: outcome, startedWith: startedWith)
            }
        }
    }

    private func finishLinkFetch(_ work: ClipboardLinkFetches.Work, outcome: ClipboardLinkFetcher.Outcome, startedWith: ClipboardStore?) {
        linkPreviews.running[work.token] = nil
        defer { startLinkFetches() }
        // Not the run that asked (the module stopped, and perhaps started again): the answer is thrown away, untouched.
        guard let store, store === startedWith else { return }
        // The card's item is gone, or changed, or may not be read any more (it went into a locked board): nothing of the answer is kept.
        guard isStillWanted(work) else {
            linkPreviews.known.remove(work.hash)
            return
        }
        // A read that failed stays in `known`: it is not tried again in this run.
        guard case .read(let title, let image) = outcome else { return }
        var hasImage = false
        if let image, let name = currentItem(work.itemID)?.linkPreviewFileName {
            do {
                try store.saveLinkPreviewImage(image, fileName: name)
                hasImage = true
            } catch {
                // Never what was read, only that it failed.
                let nsError = error as NSError
                context?.logger.error("Saving a link picture failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))")
            }
        }
        update { history in
            history.setLinkPreview(ClipboardLinkPreview(title: title, hasImage: hasImage), for: work.itemID)
            return []
        }
        linkPreviews.known.remove(work.hash)
    }
}
