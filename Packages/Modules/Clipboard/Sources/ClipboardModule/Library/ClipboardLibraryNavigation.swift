import Foundation

/// The library's back and forward list, like Finder's: where the user has been, one place per destination, not per click.
/// A value, so the rules are tested without a window; the model decides which changes are a new place and which only change
/// the one you are on. Not stored anywhere.
nonisolated struct ClipboardLibraryNavigation: Equatable, Sendable {
    /// What the window shows: the sidebar's choice, the kind filter, the search text, and the card picked there. The pick is part of
    /// the place, as the last one made while it was on show, so going back finds the list the way it was left.
    struct Place: Equatable, Sendable {
        var selection: ClipboardLibrarySelection
        var kindFilter: ClipboardKind?
        var searchText: String
        var selectedID: UUID?
    }

    /// The most places kept; the oldest go first.
    static let limit = 50

    private(set) var places: [Place]
    private(set) var index = 0

    init(start: Place) {
        places = [start]
    }

    var current: Place { places[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < places.count - 1 }

    /// A new destination. Where you are already is not one; anything ahead of you is dropped, since this starts a new way forward.
    mutating func visit(_ place: Place) {
        guard place != current else { return }
        places.removeSubrange((index + 1)...)
        places.append(place)
        if places.count > Self.limit { places.removeFirst(places.count - Self.limit) }
        index = places.count - 1
    }

    /// The place you are on changes without becoming another: typing in the search field, picking a card. When it ends up as the place
    /// before it they are one (true), so going back never does nothing the user can see.
    @discardableResult
    mutating func revise(_ place: Place) -> Bool {
        places[index] = place
        guard index > 0, places[index - 1] == place else { return false }
        places.remove(at: index)
        index -= 1
        return true
    }

    mutating func back() -> Place? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    mutating func forward() -> Place? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }

    /// Takes out the places that cannot be shown any more (a board that was deleted, an app with no items left), except the one you are
    /// on, and joins neighbours that become equal.
    mutating func removePlaces(where isGone: (Place) -> Bool) {
        var kept: [Place] = []
        var newIndex = 0
        for (position, place) in places.enumerated() {
            guard position == index || !isGone(place) else { continue }
            if let last = kept.last, last == place {
                // The same place twice in a row: one stays, and it is the one you are on if you are on either.
                if position == index { newIndex = kept.count - 1 }
                continue
            }
            if position == index { newIndex = kept.count }
            kept.append(place)
        }
        places = kept
        index = newIndex
    }
}
