/// Where a view is drawn, which decides its colors: light on the notch's black, or the system's in the library window
/// and the floating panel.
enum ClipboardLook {
    case notch
    case library
    case panel

    /// The search field takes the keyboard when its window becomes key (the notch's panel, the floating panel) instead of
    /// only when asked, since there is nothing else in those windows to type into.
    var focusesWithWindow: Bool { self != .library }
}
