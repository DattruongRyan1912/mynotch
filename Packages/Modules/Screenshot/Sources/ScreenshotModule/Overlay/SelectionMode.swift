import CoreGraphics

/// What the overlay lets the user pick.
nonisolated enum SelectionMode: Equatable, Sendable {
    /// A region only.
    case region
    /// A region, or, after Space, a window.
    case regionOrWindow
    /// A region whose text is read instead of saved.
    case ocrRegion
    /// The three ways to pick what to record: the same as `region` and `regionOrWindow`, with the hints saying "quay", and a
    /// window alone, which starts on windows and has no whole-screen key.
    case recordRegion
    case recordRegionOrWindow
    case recordWindow

    /// Whether Space switches between picking a region and picking a window.
    var switchesWithSpace: Bool { self == .regionOrWindow || self == .recordRegionOrWindow }
    var startsOnWindows: Bool { self == .recordWindow }
    var hasWholeScreenKey: Bool { self != .recordWindow }
}

/// What the user picked in the overlay.
nonisolated enum CaptureResult: Equatable, Sendable {
    /// Crop rect in the display's frozen image: pixels, origin at its top-left, y down.
    case region(displayID: CGDirectDisplayID, pixelRect: CGRect)
    case window(CGWindowID)
    case fullScreen(displayID: CGDirectDisplayID)
}
