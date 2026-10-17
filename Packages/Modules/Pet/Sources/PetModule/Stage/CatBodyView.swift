import AppKit
import NotchUI
import SwiftUI

/// Where the cat plays on a notch, and what the notch is asked for it.
nonisolated struct CatBodyLayout: Equatable, Sendable {
    /// The room asked for on each side of a hardware notch's camera: the width of the notch's top row is the camera's and twice this.
    static let wingRoom: CGFloat = 100
    /// The width asked of a virtual notch's body, which is wider than the narrowest of them is and no wider than the widest is without it.
    static let virtualWidth: CGFloat = 280

    let kind: NotchKind
    let place: PlayPlace

    /// Whether the cat plays in the top row of this notch: always on one with no camera (a strip under a virtual notch is a waste of its
    /// height, with room in the body), and on one with a camera unless the user chose the strip.
    var playsInBody: Bool { kind == .virtual || place == .portal }

    /// How wide the top row is asked to be, from the camera's width on a hardware notch.
    func requestedWidth(cameraWidth: CGFloat) -> CGFloat {
        kind == .hardware ? cameraWidth + 2 * Self.wingRoom : Self.virtualWidth
    }
}

/// The characters in the top row of the notch, in place of the strip: on a virtual notch one lane across the body, on a hardware one two
/// lanes, one each side of the camera, which they go from one to the other of through a portal.
///
/// The activity is one for every display, so this view is on each of them, and it is for the display it finds itself on to say whether it
/// has anything to show: a screen the user gave no character is asked for no room (the wings would cover the menu bar's items for nothing)
/// and draws nothing. Which display it is on it finds out once it is in a window, a turn of the main loop after it is made, and until it
/// has it asks for nothing and draws nothing: the notch is not made wider for a moment on a screen that turns out to want nothing.
struct CatBodyView: View {
    let stages: CatStages
    let place: PlayPlace
    @Environment(\.notchGeometry) private var geometry
    @Environment(\.notchIsOnScreen) private var isOnScreen
    @State private var display: DisplayID?

    var body: some View {
        let layout = CatBodyLayout(kind: geometry?.kind ?? .virtual, place: place)
        let hasPets = display.map { stages.hasCharacters(on: $0) } ?? false
        Group {
            if isOnScreen, layout.playsInBody, hasPets {
                CatBody(stages: stages, geometry: geometry)
                    .notchBodyWidth(layout.requestedWidth(cameraWidth: geometry?.notchSize.width ?? 0))
            } else {
                Color.clear
            }
        }
        .background(DisplayProbe(stages: stages, display: $display))
    }
}

/// Tells a view which display it is on, from the window it is in, and again whenever that changes: it is there whether or not the view it
/// is behind has anything on show, which is how a screen that was given no character is seen to be given one.
struct DisplayProbe: NSViewRepresentable {
    let stages: CatStages
    @Binding var display: DisplayID?

    func makeNSView(context: Context) -> DisplayProbeView { DisplayProbeView(stages: stages) }

    func updateNSView(_ view: DisplayProbeView, context: Context) {
        let binding = $display
        view.report = { display in if binding.wrappedValue != display { binding.wrappedValue = display } }
        view.look()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: DisplayProbeView, context: Context) -> CGSize? { .zero }
}

final class DisplayProbeView: NSView {
    private let stages: CatStages
    var report: (DisplayID) -> Void = { _ in }
    private var listening: [any NSObjectProtocol] = []

    init(stages: CatStages) {
        self.stages = stages
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        listening.forEach(stages.notifications.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        listening.forEach(stages.notifications.removeObserver)
        listening = []
        if window != nil {
            let names = [NSWindow.didChangeScreenNotification, NSApplication.didChangeScreenParametersNotification]
            listening = names.map { name in
                stages.notifications.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.look() }
                }
            }
        }
        look()
    }

    /// Whether the display has been reported at least once (for tests).
    private(set) var hasReported = false

    /// Reports the display the window is on now, to be changed in the view's state when SwiftUI is not in the middle of drawing it.
    func look() {
        guard let window else { return }
        let display = stages.displayOf(window) ?? CatStages.unknownDisplay
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                self?.hasReported = true
                self?.report(display)
            }
        }
    }
}

struct CatBody: NSViewRepresentable {
    let stages: CatStages
    let geometry: NotchGeometry?

    func makeNSView(context: Context) -> CatBodyContainer { CatBodyContainer(stages: stages) }

    func updateNSView(_ view: CatBodyContainer, context: Context) { view.configure(geometry: geometry) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: CatBodyContainer, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 300, height: 32))
    }
}

/// Where the camera is in the top row of a hardware notch, as a stretch of the row from the left.
nonisolated enum Cutout {
    /// From the geometry: the notch's body is as wide as the camera's cutout and in the middle of the row, which is as wide as the notch.
    static func geometric(rowWidth: CGFloat, cameraWidth: CGFloat) -> ClosedRange<CGFloat> {
        let low = max((rowWidth - cameraWidth) / 2, 0)
        return low...max(low + cameraWidth, low)
    }

    /// From the screen's own: the areas of the menu bar either side of the camera run from the screen's edges to it, so the camera is from
    /// the left edge and the width of the one on the left to the right edge less the width of the one on the right, in screen coordinates.
    /// (Only the widths are used, as `ScreenDescriptor` does: whatever space the areas' own origins are in, these are right for a screen
    /// anywhere in the arrangement of displays.) Nil for a screen with no camera.
    static func measured(screenFrame: CGRect, leftWidth: CGFloat?, rightWidth: CGFloat?) -> ClosedRange<CGFloat>? {
        guard let leftWidth, let rightWidth, screenFrame.width - leftWidth - rightWidth > 0 else { return nil }
        return (screenFrame.minX + leftWidth)...(screenFrame.maxX - rightWidth)
    }
}

/// The view that holds the characters' views in the top row of one notch: one across the body of a virtual notch, two (left and right of
/// the camera) on a hardware one. It takes a click only where one of them has a character. Which stage shows the views is for the registry
/// to say, by the display the window is on (`CatStages`).
///
/// Where the wings are is where the camera is on the screen, which is a thing of the window and its screen and not of this view's bounds, so
/// AppKit does not lay the view out when it changes: a window moves (the screens are plugged in, one wakes, the Space or the resolution
/// changes), a window that had no screen when the wings were first laid out gets one. The container is laid out again for every one of these
/// that can be heard of (`placeChanged`), and the stage's own look, a few times a second, finds the ones that cannot (`isStale`).
final class CatBodyContainer: NSView {
    private let stages: CatStages
    private var geometry: NotchGeometry?
    private(set) var lane: CatSpriteView?
    private(set) var leftWing: CatSpriteView?
    private(set) var rightWing: CatSpriteView?
    /// The screen `window` is on, as far as the camera is concerned: its frame and the widths of the areas of the menu bar either side of
    /// the camera (nil for a screen with none). A test says what they are.
    var screenAreas: (NSWindow) -> (frame: CGRect, left: CGFloat?, right: CGFloat?)? = { window in
        window.screen.map { ($0.frame, $0.auxiliaryTopLeftArea?.width, $0.auxiliaryTopRightArea?.width) }
    }

    /// Where it hears of its window moving and changing screen, and of the screens changing: a test says where, before the view is in a
    /// window.
    var notifications: NotificationCenter = .default
    /// The center it is listening on, if it is: the one `notifications` was when it went into a window.
    private var listening: NotificationCenter?
    /// The camera the wings were last laid out for, in this view's coordinates; nil while there is no pair of wings to lay out.
    private var laidOutCutout: ClosedRange<CGFloat>?

    init(stages: CatStages) {
        self.stages = stages
        super.init(frame: .zero)
        // The views it holds draw on layers, and a layer under them that is a layer of its own is what Core Animation does anyway.
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The views the cat is shown in.
    var catViews: [CatSpriteView] { [lane, leftWing, rightWing].compactMap { $0 } }

    private var kind: NotchKind { geometry?.kind ?? .virtual }

    func configure(geometry: NotchGeometry?) {
        self.geometry = geometry
        arrange()
        needsLayout = true
    }

    /// One lane for a notch with no camera and a pair of wings for one with: the views are made again when the kind changes (a change of
    /// the setting does not, but a view that moves to another kind of display does).
    private func arrange() {
        let wantsWings = kind == .hardware
        guard wantsWings ? lane != nil || leftWing == nil : leftWing != nil || lane == nil else { return }
        catViews.forEach { $0.removeFromSuperview() }
        (lane, leftWing, rightWing) = (nil, nil, nil)
        if wantsWings {
            let (left, right) = (CatSpriteView(stages: stages, role: .leftWing), CatSpriteView(stages: stages, role: .rightWing))
            left.partner = right
            right.partner = left
            (leftWing, rightWing) = (left, right)
            [left, right].forEach(addSubview)
        } else {
            let view = CatSpriteView(stages: stages, role: .lane)
            lane = view
            addSubview(view)
        }
    }

    /// Where the camera is in this view's own coordinates: as the screen reports it when this view is on one with a camera, else as the
    /// geometry says.
    func cutout() -> ClosedRange<CGFloat> {
        if let window, let areas = screenAreas(window),
           let range = Cutout.measured(screenFrame: areas.frame, leftWidth: areas.left, rightWidth: areas.right) {
            let onScreen = CGRect(x: range.lowerBound, y: window.frame.minY, width: range.upperBound - range.lowerBound, height: 1)
            let local = convert(window.convertFromScreen(onScreen), from: nil)
            let low = min(max(local.minX, 0), bounds.width)
            return low...min(max(local.maxX, low), bounds.width)
        }
        return Cutout.geometric(rowWidth: bounds.width, cameraWidth: geometry?.notchSize.width ?? 0)
    }

    // MARK: Following the window

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        listening?.removeObserver(self)
        listening = nil
    }

    /// In a window it hears of the window moving and changing screen and of the screens changing, and lays out for where it is now. The
    /// window it was laid out in may not be the one it is in, and a window moved into its place is not heard of if it was never listened to.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            notifications.addObserver(self, selector: #selector(placeChanged), name: name, object: window)
        }
        notifications.addObserver(self, selector: #selector(placeChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        listening = notifications
        needsLayout = true
    }

    /// The window moved, changed screen, or the screens were arranged again: the camera is not where the wings were laid out for.
    @objc private func placeChanged(_ notification: Notification) {
        needsLayout = true
    }

    /// Whether the camera is somewhere else than the wings were laid out for, which nothing tells this view when what it is on changes
    /// silently: the stage looks, and lays the view out again if so.
    var wingsAreStale: Bool {
        leftWing != nil && cutout() != laidOutCutout
    }

    /// Whether the views are arranged for what is not so any more: the camera is elsewhere, or the window is on another display, whose
    /// stage is the one that should show them.
    var isStale: Bool {
        wingsAreStale || catViews.contains(where: stages.isRoutedElsewhere)
    }

    override func layout() {
        super.layout()
        laidOutCutout = nil
        if let lane {
            lane.frame = bounds
        } else if let leftWing, let rightWing {
            let camera = cutout()
            laidOutCutout = camera
            leftWing.frame = CGRect(x: 0, y: 0, width: camera.lowerBound.rounded(), height: bounds.height)
            rightWing.frame = CGRect(x: camera.upperBound.rounded(), y: 0, width: max(bounds.width - camera.upperBound.rounded(), 0), height: bounds.height)
        }
        for view in catViews {
            stages.reroute(view)
            view.stage?.hostDidMove(view)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for view in catViews.reversed() {
            if let hit = view.hitTest(local) { return hit }
        }
        return nil
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
