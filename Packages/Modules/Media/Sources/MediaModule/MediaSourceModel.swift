import Foundation
import Observation

/// One chip of the row above the player: a source, as the user reads it.
struct MediaSourceChip: Identifiable, Equatable {
    var id: MediaSourceID
    /// The track, short; the view cuts it to the chip's width.
    var title: String
    /// What the tooltip adds: the artist, or the site of a tab.
    var detail: String
    var isPlaying: Bool
    /// The notch follows this source (the closed notch, the lock screen, the hotkeys).
    var isPrimary: Bool
    /// The user pinned it as the one the notch follows.
    var isPinned: Bool
    /// The player below shows this source.
    var isShown: Bool
    /// The app whose icon the chip wears: the player's, or the browser of a tab.
    var iconBundleID: String?
}

/// What the Media tab shows of the sources and does about a tap, for the views, which read it directly: the chips (only with two
/// sources or more), which of them the player shows, and the apps the user did not let MyNotch control, for Settings. The hub
/// keeps it up to date and acts on what the views ask.
@Observable
final class MediaSourceModel {
    /// Chips are for choosing between sources: with one, there is nothing to choose.
    static let minimumChips = 2

    private(set) var chips: [MediaSourceChip] = []
    /// The source the player shows, and the one the notch follows; nil while there is none.
    private(set) var displayedID: MediaSourceID?
    private(set) var primaryID: MediaSourceID?
    /// The apps that could not be read or controlled because the user did not let MyNotch (Automation), by name, for the hint in Settings.
    private(set) var deniedApps: [String] = []
    /// The Media tab is on screen right now, which is what makes the apps worth asking about.
    private(set) var isTabVisible = false

    @ObservationIgnored var onSelect: (MediaSourceID) -> Void = { _ in }
    @ObservationIgnored var onTogglePin: (MediaSourceID) -> Void = { _ in }
    @ObservationIgnored var onVisibilityChange: (Bool) -> Void = { _ in }

    var showsChips: Bool { chips.count >= Self.minimumChips }

    /// The player shows the source the notch follows, whose lyrics, bars and tint it has.
    var displayIsPrimary: Bool { displayedID == primaryID }

    func select(_ id: MediaSourceID) { onSelect(id) }
    func togglePin(_ id: MediaSourceID) { onTogglePin(id) }

    /// The tab appeared or went away. Called by the view, so a tab that is not on screen costs nothing.
    func setTabVisible(_ isVisible: Bool) {
        guard isVisible != isTabVisible else { return }
        isTabVisible = isVisible
        onVisibilityChange(isVisible)
    }

    /// Assigns only what changed: the views redraw for each assignment.
    func update(chips newChips: [MediaSourceChip], displayedID: MediaSourceID?, primaryID: MediaSourceID?) {
        if newChips != chips { chips = newChips }
        if displayedID != self.displayedID { self.displayedID = displayedID }
        if primaryID != self.primaryID { self.primaryID = primaryID }
    }

    func setDeniedApps(_ names: [String]) {
        if names != deniedApps { deniedApps = names }
    }

    /// Back to nothing, when the module stops.
    func reset() {
        update(chips: [], displayedID: nil, primaryID: nil)
        setDeniedApps([])
        if isTabVisible { isTabVisible = false }
    }
}
