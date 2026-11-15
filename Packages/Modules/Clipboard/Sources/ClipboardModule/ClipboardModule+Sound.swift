import Foundation

/// The optional sounds. Both start from the setting, so with it off nothing here reads an item.
extension ClipboardModule {
    /// A copy was recorded. Silent for what the user would not want announced: an item a password manager marked (the item carries that
    /// mark, which a marked copy sets and an unmarked one never clears), one that looks like a password or a key, and one that belongs to a
    /// board that has a lock. Excluded apps, the sensitive skip and MyNotch's own writes never get this far: the monitor drops them first.
    func playCaptureSound(for itemID: UUID?) {
        guard soundsAreOn, let itemID, let item = state.history.items.first(where: { $0.id == itemID }), !isQuiet(item) else { return }
        play(.captured)
    }

    /// An item is about to be pasted: remembers whether its paste is one the user would not want announced, the same items as for a capture
    /// (the settings caption promises both). The ⌘V goes out a moment later, and only the latest paste has one waiting, since a paste
    /// cancels the one before it. Nothing is read of the item while sounds are off.
    func notePasteForSound(of item: ClipboardItem) {
        pasteIsQuiet = !soundsAreOn || isQuiet(item)
    }

    /// ⌘V went out for a paste of ours. Called by the gate that every ⌘V passes, so it is never for a paste that fell back to a copy,
    /// for one given up, or for one that was still waiting when the module stopped.
    func playPasteSound() {
        guard soundsAreOn, !pasteIsQuiet else { return }
        play(.pasted)
    }

    /// Flagged as a secret by the app that copied it, looking like a password or a key, or in a board that has a lock.
    private func isQuiet(_ item: ClipboardItem) -> Bool {
        item.isSensitive || state.history.protectedItemIDs.contains(item.id) || ClipboardMCPSecretFilter.hides(item)
    }

    private var soundsAreOn: Bool {
        guard let context, let keys else { return false }
        return context.settings.value(keys.playSounds)
    }

    private func play(_ sound: ClipboardSound) {
        guard soundGate.admit(at: soundClock()) else { return }
        soundPlayer.play(sound)
    }
}
