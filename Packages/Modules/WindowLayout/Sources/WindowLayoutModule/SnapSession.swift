import CoreGraphics
import Foundation
import MyNotchCore
import NotchUI
import Observation
import SwiftUI

/// What the system tells the module about the mouse and the keyboard.
nonisolated enum DragEvent: Equatable, Sendable {
    case down
    /// The pointer moved with the button down; `time` is when, in seconds on a clock that only goes forward.
    case dragged(CGPoint, time: TimeInterval)
    case up(CGPoint)
    /// The Escape key went down. Only sent while Escape is watched.
    case escape
}

/// The mouse and key monitors, behind a protocol so tests send the events themselves. Points are AppKit screen
/// coordinates (y grows up).
protocol DragEventSource: AnyObject {
    func start(_ handler: @escaping @MainActor (DragEvent) -> Void)
    func stop()
    /// Escape is watched only while a window is being dragged, so no key monitor runs the rest of the time.
    func setWatchingEscape(_ watching: Bool)
}

/// The translucent overlay that shows where a drop would put the window. Frames are AppKit screen coordinates.
protocol SnapPreview: AnyObject {
    func show(frame: CGRect)
    func hide()
    /// The module stops: the window goes for good.
    func dismiss()
}

/// One display's visible area: what is left of it once the menu bar and the Dock are out.
nonisolated struct SnapScreen: Equatable, Sendable {
    let id: CGDirectDisplayID
    let visibleFrame: CGRect
}

nonisolated struct SnapScreens: Equatable, Sendable {
    let screens: [SnapScreen]
    /// The primary display's height, for turning AppKit frames into Accessibility ones (`SnapSpace`).
    let primaryHeight: CGFloat
}

/// What the tiles in the notch show: which layouts, and which target the pointer is over.
@Observable
final class SnapTilesModel {
    var layouts: [SnapLayout] = []
    var hovered: SnapTarget?
}

/// Follows one window drag from the first press to the release: recognises it, opens the tiles in the notch when the
/// pointer comes near, previews the target and, on a release over a tile, moves the window there.
final class SnapSession {
    /// How far around the open tiles the pointer may stray before they close, so the way to a tile is not a tightrope.
    static let keepOpenMargin: CGFloat = 24
    /// The window is moved this long after the release. The app that owns it is still tracking the drag when the button
    /// comes up and puts the window where the pointer is; a move made before it finishes would be undone.
    static let settleDelay = Duration.milliseconds(80)

    /// Everything the session reads or does outside itself.
    struct Environment {
        let isTrusted: () -> Bool
        /// The displays that show a notch now.
        let notches: () -> [NotchDisplay]
        let screens: () -> SnapScreens
        let options: () -> SnapOptions
        /// Opens the notch with these tiles in it.
        let showTiles: (AnyView) -> Void
        let hideTiles: () -> Void
        /// A window took the place of a tile: the light tap on the trackpad that goes with it, which the interface gives
        /// unless the user turned taps off.
        let feel: () -> Void
    }

    /// The tiles are open on `notch`, with these layouts.
    private struct Open {
        let notch: NotchDisplay
        let layouts: [SnapLayout]
        let options: SnapOptions
        var content: CGRect { notch.geometry.contentFrame(height: SnapTiles.height, in: notch.screenFrame) }
    }

    let tiles = SnapTilesModel()
    private let environment: Environment
    private let detector: WindowDragDetector
    private let events: any DragEventSource
    private let makePreview: () -> any SnapPreview
    private let scheduler: any Scheduler
    private var preview: (any SnapPreview)?
    private var open: Open?
    /// Escape was pressed: the rest of this drag does nothing.
    private var isCancelled = false
    private var pendingMove: ScheduledAction?

    /// `makePreview` is called when the first preview is shown, so a window is only made once it is needed.
    init(
        environment: Environment, probe: any WindowProbe, events: any DragEventSource,
        makePreview: @escaping () -> any SnapPreview, scheduler: any Scheduler
    ) {
        self.environment = environment
        detector = WindowDragDetector(probe: probe, isTrusted: environment.isTrusted)
        self.events = events
        self.makePreview = makePreview
        self.scheduler = scheduler
    }

    func handle(_ event: DragEvent) {
        switch event {
        case .down:
            finishDrag()
            detector.mouseDown()
        case .dragged(let point, let time):
            dragged(to: point, at: time)
        case .up(let point):
            released(at: point)
        case .escape:
            guard detector.isDragging else { return }
            isCancelled = true
            closeTiles()
        }
    }

    /// The module stops: nothing stays open and no move is waiting.
    func stop() {
        pendingMove?.cancel()
        pendingMove = nil
        finishDrag()
        preview?.dismiss()
        preview = nil
    }

    // MARK: dragging

    private func dragged(to point: CGPoint, at time: TimeInterval) {
        if !detector.isDragging {
            guard detector.mouseDragged(at: time) else { return }
            isCancelled = false
            events.setWatchingEscape(true)
        }
        guard !isCancelled else { return }
        update(at: point)
    }

    /// Opens, keeps, moves or closes the tiles for a pointer at `point`, and follows the target under it.
    private func update(at point: CGPoint) {
        guard let notch = environment.notches().first(where: { $0.screenFrame.containsMouseLocation(point) }) else {
            return closeTiles()
        }
        // Another display's notch: the tiles go there, once the pointer is near it.
        if let open, open.notch.id != notch.id { closeTiles() }
        if open == nil {
            guard Self.isNear(notch, point) else { return }
            openTiles(on: notch)
        }
        guard let open else { return }
        guard Self.keepsOpen(open, at: point) else { return closeTiles() }
        follow(SnapTiles.target(at: point, layouts: open.layouts, content: open.content), in: open)
    }

    private static func isNear(_ notch: NotchDisplay, _ point: CGPoint) -> Bool {
        notch.geometry.dragHitRect(for: .closed, in: notch.screenFrame).contains(point)
    }

    /// Near the notch, or over the open tiles and a margin around them, straight up to the top of the screen.
    private static func keepsOpen(_ open: Open, at point: CGPoint) -> Bool {
        if isNear(open.notch, point) { return true }
        let content = open.content.insetBy(dx: -keepOpenMargin, dy: -keepOpenMargin)
        let column = CGRect(x: content.minX, y: content.minY, width: content.width, height: open.notch.screenFrame.maxY + 1 - content.minY)
        return column.contains(point)
    }

    private func openTiles(on notch: NotchDisplay) {
        let options = environment.options()
        open = Open(notch: notch, layouts: options.layouts, options: options)
        tiles.layouts = options.layouts
        tiles.hovered = nil
        environment.showTiles(AnyView(SnapTilesView(model: tiles)))
    }

    private func closeTiles() {
        guard open != nil else { return }
        open = nil
        tiles.hovered = nil
        preview?.hide()
        environment.hideTiles()
    }

    /// Highlights `target` and previews where it would put the window; with no target, or no display to measure, no preview.
    private func follow(_ target: SnapTarget?, in open: Open) {
        guard target != tiles.hovered else { return }
        tiles.hovered = target
        guard let target, let area = visibleFrame(of: open.notch) else {
            preview?.hide()
            return
        }
        let preview = preview ?? makePreview()
        self.preview = preview
        preview.show(frame: target.frame(in: area, gap: open.options.gap.points))
    }

    private func visibleFrame(of notch: NotchDisplay) -> CGRect? {
        environment.screens().screens.first { $0.id == notch.id }?.visibleFrame
    }

    // MARK: letting go

    private func released(at point: CGPoint) {
        let window = detector.window
        let drop = open.flatMap { open in
            SnapTiles.target(at: point, layouts: open.layouts, content: open.content).map { (open, $0) }
        }
        let wasCancelled = isCancelled
        finishDrag()
        guard let window, let (open, target) = drop, !wasCancelled else { return }
        pendingMove = scheduler.schedule(after: Self.settleDelay) { [weak self] in
            self?.move(window, to: target, on: open.notch, gap: open.options.gap)
        }
    }

    /// Ends whatever drag was on: the tiles, the preview and Escape's watch go, and the detector starts over.
    private func finishDrag() {
        closeTiles()
        detector.end()
        isCancelled = false
        events.setWatchingEscape(false)
    }

    private func move(_ window: any SnapWindow, to target: SnapTarget, on notch: NotchDisplay, gap: SnapGap) {
        pendingMove = nil
        let screens = environment.screens()
        guard let area = screens.screens.first(where: { $0.id == notch.id })?.visibleFrame else { return }
        let frame = target.frame(in: area, gap: gap.points)
        let snapped = window.place(SnapPlacement(
            frame: SnapSpace.accessibilityFrame(of: frame, primaryHeight: screens.primaryHeight),
            area: SnapSpace.accessibilityFrame(of: area, primaryHeight: screens.primaryHeight),
            anchor: target.layout.zones[target.zone].anchor
        ))
        // An app that refused to move got nothing to feel.
        if snapped { environment.feel() }
    }
}
