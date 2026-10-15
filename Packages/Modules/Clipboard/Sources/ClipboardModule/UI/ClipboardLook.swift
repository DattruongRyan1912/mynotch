import AppKit

/// Where a view is drawn, which decides its colors: light on the notch's black, or the system's in the library window
/// and the floating panel.
enum ClipboardLook {
    case notch
    case library
    case panel

    /// The search field takes the keyboard when its window becomes key (the notch's panel, the floating panel) instead of
    /// only when asked, since there is nothing else in those windows to type into.
    var focusesWithWindow: Bool { self != .library }

    /// The appearance of an AppKit text field in this look. The black notch's fields are dark whatever the system's appearance is;
    /// on Liquid Glass, and in the windows that follow the system, nil, which is the window's own, so the field and its text are
    /// light or dark with the glass or the window behind them.
    func fieldAppearance(onGlass: Bool) -> NSAppearance.Name? {
        self == .notch && !onGlass ? .darkAqua : nil
    }
}
