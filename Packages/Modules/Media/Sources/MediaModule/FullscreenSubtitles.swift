import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// A display the subtitles can be put on, as the fullscreen check sees it.
struct SubtitleOverlayDisplay: Equatable {
    var id: CGDirectDisplayID
    /// Global CG coordinates (top-left origin), like a window's frame through Accessibility.
    var bounds: CGRect
    /// AppKit coordinates (bottom-left origin), where the window goes.
    var frame: CGRect
}

/// Where a film's subtitles go while its player fills a screen: the display a fullscreen window of the player is on, as subtitles
/// on the film would be. Another app filling a screen is no film: the player's own windows are the only ones that count.
///
/// Whether a window is fullscreen is what the app says through Accessibility, not its size: Chrome's fullscreen window starts one
/// point below the camera housing, where a window zoomed to the menu bar starts too, so the two cannot be told apart by their frames.
enum FullscreenSubtitleRule {
    /// The text's height against the screen's, as a player sizes its subtitles.
    static let sizeOfScreen = 0.045
    static let minimumFontSize = 22.0
    /// Two lines of text and the room around them.
    static let heightInLines = 3.2
    /// How far the lines sit above the bottom edge, as a share of the screen's height: the user's choice, within this range.
    static let bottomGap = 0.07
    static let bottomGapRange = 0.0...0.6
    /// How much of the width the lines may take.
    static let widthOfScreen = 0.8
    /// How much larger or smaller than a player's the user made them, by pinching or scrolling on them.
    static let scaleRange = 0.5...2.5
    /// What one notch of a mouse wheel, or a point of a trackpad's scroll, scales them by.
    static let wheelStep = 1.08
    static let preciseStep = 0.005

    /// The display that holds the middle of one of the player's fullscreen windows, given in global CG coordinates.
    static func display(fullscreenWindows: [CGRect], displays: [SubtitleOverlayDisplay]) -> SubtitleOverlayDisplay? {
        for window in fullscreenWindows {
            let middle = CGPoint(x: window.midX, y: window.midY)
            if let display = displays.first(where: { $0.bounds.contains(middle) }) { return display }
        }
        return nil
    }

    /// A display for the lines shown by hand rather than over a fullscreen film: the one with the middle of the player's window, the
    /// first one without a window found.
    static func display(of window: CGRect?, displays: [SubtitleOverlayDisplay]) -> SubtitleOverlayDisplay? {
        guard let window else { return displays.first }
        return displays.first { $0.bounds.contains(CGPoint(x: window.midX, y: window.midY)) } ?? displays.first
    }

    static func fontSize(screenHeight: CGFloat, scale: Double = 1) -> CGFloat {
        max(screenHeight * sizeOfScreen, minimumFontSize) * CGFloat(clampedScale(scale))
    }

    static func clampedScale(_ scale: Double) -> Double {
        min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// The height the lines sit at with the band's bottom at `minY` on `screen`, within the range.
    static func bottomGap(forBandAt minY: CGFloat, on screen: CGRect) -> Double {
        let gap = Double((minY - screen.minY) / screen.height)
        return min(max(gap, bottomGapRange.lowerBound), bottomGapRange.upperBound)
    }

    /// The band across the bottom of `screen` the lines are drawn in, in AppKit coordinates.
    static func frame(on screen: CGRect, bottomGap: Double = bottomGap, scale: Double = 1) -> CGRect {
        let height = fontSize(screenHeight: screen.height, scale: scale) * heightInLines
        let width = screen.width * widthOfScreen
        let gap = min(max(bottomGap, bottomGapRange.lowerBound), bottomGapRange.upperBound)
        // Whole points, as the window takes them.
        return CGRect(x: screen.midX - width / 2, y: screen.minY + screen.height * gap, width: width, height: height).integral
    }
}

extension NowPlayingStore {
    /// The subtitle on the film at `date`: empty between two, as on a player.
    func subtitle(at date: Date) -> String {
        lyric(at: date)?.text ?? ""
    }
}

/// The lines as a player shows them: white, outlined in black, centred at the bottom, and nothing between two.
struct FullscreenSubtitleView: View {
    let store: NowPlayingStore
    let fontSize: CGFloat

    var body: some View {
        LyricTimeline(store: store) { date in
            let text = store.subtitle(at: date)
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                // An outline more than a shadow: the lines are read on a bright film as on a dark one.
                .shadow(color: .black, radius: 1)
                .shadow(color: .black, radius: 2)
                .shadow(color: .black.opacity(0.6), radius: 4)
                // Almost nothing, but drawn: a press or a pinch anywhere on the lines' box is theirs, not only on the letters.
                .background(Color.black.opacity(0.01).padding(-8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityLabel("Phụ đề")
                .accessibilityValue(text)
        }
        .environment(\.notchIsOnScreen, true)
    }
}

/// The window the subtitles are drawn in: over the fullscreen film, on its Space, and never in the way. It has no background, so
/// the pointer goes through everywhere but the letters (macOS passes a press on a pixel nothing is drawn in to the window under it),
/// and it never takes the keyboard: the player's own controls work as before. A press on the lines drags them up or down; a pinch
/// or a scroll on them makes them larger or smaller.
final class FullscreenSubtitlePanel: NSPanel {
    /// Where the band's bottom may go while it is dragged.
    var allowedMinY: ClosedRange<CGFloat> = -CGFloat.greatestFiniteMagnitude...CGFloat.greatestFiniteMagnitude
    /// The band was let go with its bottom at this height.
    var onDragged: (CGFloat) -> Void = { _ in }
    /// A pinch or a scroll: the lines are to be this many times their size.
    var onScaled: (Double) -> Void = { _ in }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Up and down only, the lines staying centred: the window follows the pointer until the button is let go.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .magnify:
            return onScaled(1 + Double(event.magnification))
        case .scrollWheel:
            // Up, or away from the user on a trackpad, makes them larger.
            let delta = Double(event.scrollingDeltaY)
            guard delta != 0 else { return }
            return onScaled(event.hasPreciseScrollingDeltas
                ? 1 + delta * FullscreenSubtitleRule.preciseStep
                : (delta > 0 ? FullscreenSubtitleRule.wheelStep : 1 / FullscreenSubtitleRule.wheelStep))
        case .leftMouseDown:
            break
        default:
            return super.sendEvent(event)
        }
        let start = NSEvent.mouseLocation.y
        let origin = frame.origin
        while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let y = origin.y + NSEvent.mouseLocation.y - start
            setFrameOrigin(NSPoint(x: origin.x, y: min(max(y, allowedMinY.lowerBound), allowedMinY.upperBound)))
            if next.type == .leftMouseUp { break }
        }
        if frame.minY != origin.y { onDragged(frame.minY) }
    }
}

/// Puts the subtitles over the film while its player fills a screen, and takes them away when it does not; or keeps them up all the
/// time the user wants them, on the screen of the player's window. It looks while it is on only: the setting is on and the film has
/// subtitles the user loaded. What can make the player fill a screen or stop (a Space change, another app in front, a display plugged
/// in) has it look again, and once more as the Space's animation ends.
@Observable
final class FullscreenSubtitleOverlay {
    /// What the overlay reads of the system; tests give their own.
    struct Environment {
        /// The frames of the windows of these processes that are fullscreen, in global CG coordinates.
        var fullscreenWindows: @MainActor (Set<pid_t>) -> [CGRect]
        var displays: @MainActor () -> [SubtitleOverlayDisplay]
        /// The largest window on screen of these processes, in global CG coordinates.
        var playerWindow: @MainActor (Set<pid_t>) -> CGRect? = Environment.largestWindow
        /// The processes of the apps with these bundle IDs.
        var processes: @MainActor ([String]) -> Set<pid_t>
        /// Listens for what can change the answer and returns what stops listening.
        var observe: (@escaping @MainActor () -> Void) -> () -> Void

        static let system = Environment(
            fullscreenWindows: Self.fullscreenWindows,
            displays: Self.screens,
            processes: { bundleIDs in
                Set(bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }.map(\.processIdentifier))
            },
            observe: { handler in
                let workspace = NSWorkspace.shared.notificationCenter
                let subscriptions: [(NotificationCenter, Notification.Name)] = [
                    (workspace, NSWorkspace.activeSpaceDidChangeNotification),
                    (workspace, NSWorkspace.didActivateApplicationNotification),
                    (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
                ]
                let tokens = subscriptions.map { center, name in
                    (center, center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { handler() } })
                }
                return { tokens.forEach { $0.0.removeObserver($0.1) } }
            }
        )

        /// Through Accessibility, which the app has for its other features; without it nothing is fullscreen and nothing is shown.
        private static func fullscreenWindows(of processes: Set<pid_t>) -> [CGRect] {
            processes.flatMap { pid -> [CGRect] in
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.3)
                var windows: CFTypeRef?
                guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
                      let windows = windows as? [AXUIElement] else { return [] }
                return windows.compactMap { window in
                    var fullscreen: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen) == .success,
                          (fullscreen as? Bool) == true else { return nil }
                    return frame(of: window)
                }
            }
        }

        private static func frame(of element: AXUIElement) -> CGRect? {
            var position: CFTypeRef?
            var size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size else { return nil }
            var origin = CGPoint.zero
            var extent = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            return CGRect(origin: origin, size: extent)
        }

        static func largestWindow(of processes: Set<pid_t>) -> CGRect? {
            guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                return nil
            }
            return list.compactMap { info -> CGRect? in
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, processes.contains(pid),
                      info[kCGWindowLayer as String] as? Int == 0,
                      let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
                return CGRect(dictionaryRepresentation: bounds)
            }
            .max { $0.width * $0.height < $1.width * $1.height }
        }

        private static func screens() -> [SubtitleOverlayDisplay] {
            NSScreen.screens.compactMap { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
                let id = number.uint32Value
                return SubtitleOverlayDisplay(id: id, bounds: CGDisplayBounds(id), frame: screen.frame)
            }
        }
    }

    /// Looked at again after an event, while the Space's animation plays out.
    static let rechecks: [Duration] = [.milliseconds(500), .milliseconds(1500)]

    /// The display the subtitles are over now; nil while they are not shown.
    private(set) var display: SubtitleOverlayDisplay?
    var isShown: Bool { display != nil }
    /// The subtitles came or went.
    @ObservationIgnored var onChange: () -> Void = {}
    /// The user dragged them to this height.
    @ObservationIgnored var onBottomGapChanged: (Double) -> Void = { _ in }
    /// The user pinched or scrolled them to this size.
    @ObservationIgnored var onScaleChanged: (Double) -> Void = { _ in }
    /// Up by hand, fullscreen or not.
    private(set) var isForced = false

    @ObservationIgnored private let store: NowPlayingStore
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let environment: Environment
    @ObservationIgnored private let present: (NSPanel) -> Void
    @ObservationIgnored private var panel: FullscreenSubtitlePanel?
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var playerBundleIDs: [String] = []
    @ObservationIgnored private var stopObserving: (() -> Void)?
    @ObservationIgnored private var pending: [ScheduledAction] = []
    /// How high the lines sit and how large they are, the settings' values.
    @ObservationIgnored private var bottomGap = FullscreenSubtitleRule.bottomGap
    @ObservationIgnored private var scale = 1.0

    init(store: NowPlayingStore, scheduler: any Scheduler, environment: Environment = .system, present: @escaping (NSPanel) -> Void) {
        self.store = store
        self.scheduler = scheduler
        self.environment = environment
        self.present = present
    }

    /// Over a fullscreen film while `enabled` (the setting is on and the film has subtitles), all the time while `forced` (shown by
    /// hand); the player is the app the film plays in. Safe to call with every update of the track: it looks again only when something
    /// here changed.
    func update(enabled: Bool, forced: Bool = false, playerBundleIDs: [String]) {
        guard enabled != isEnabled || forced != isForced || playerBundleIDs != self.playerBundleIDs else { return }
        isEnabled = enabled
        isForced = forced
        self.playerBundleIDs = playerBundleIDs
        let looks = enabled || forced
        if looks, stopObserving == nil {
            stopObserving = environment.observe { [weak self] in self?.evaluateSoon() }
        } else if !looks {
            stopObserving?()
            stopObserving = nil
            cancelRechecks()
        }
        evaluate()
    }

    /// The lines move to the new height at once when they are up.
    func setBottomGap(_ gap: Double) {
        guard gap != bottomGap else { return }
        bottomGap = gap
        if let display { panel?.setFrame(FullscreenSubtitleRule.frame(on: display.frame, bottomGap: gap, scale: scale), display: true) }
    }

    /// The lines take the new size at once when they are up, their bottom where it was.
    func setScale(_ scale: Double) {
        let scale = FullscreenSubtitleRule.clampedScale(scale)
        guard scale != self.scale else { return }
        self.scale = scale
        if let display { show(on: display.frame) }
    }

    private func scaled(by factor: Double) {
        let before = scale
        setScale(scale * factor)
        if scale != before { onScaleChanged(scale) }
    }

    private func dragged(to minY: CGFloat, on screen: CGRect) {
        bottomGap = FullscreenSubtitleRule.bottomGap(forBandAt: minY, on: screen)
        onBottomGapChanged(bottomGap)
    }

    /// Gone, and not listening any more.
    func close() {
        update(enabled: false, forced: false, playerBundleIDs: [])
    }

    private func evaluateSoon() {
        evaluate()
        cancelRechecks()
        pending = Self.rechecks.map { delay in scheduler.schedule(after: delay) { [weak self] in self?.evaluate() } }
    }

    private func cancelRechecks() {
        pending.forEach { $0.cancel() }
        pending = []
    }

    private func evaluate() {
        var found: SubtitleOverlayDisplay?
        if isEnabled || isForced {
            let processes = environment.processes(playerBundleIDs)
            let displays = environment.displays()
            found = FullscreenSubtitleRule.display(fullscreenWindows: environment.fullscreenWindows(processes), displays: displays)
            if found == nil, isForced {
                found = FullscreenSubtitleRule.display(of: environment.playerWindow(processes), displays: displays)
            }
        }
        guard found != display else { return }
        display = found
        if let found {
            show(on: found.frame)
        } else {
            panel?.orderOut(nil)
        }
        onChange()
    }

    private func show(on screen: CGRect) {
        let frame = FullscreenSubtitleRule.frame(on: screen, bottomGap: bottomGap, scale: scale)
        let view = FullscreenSubtitleView(store: store, fontSize: FullscreenSubtitleRule.fontSize(screenHeight: screen.height, scale: scale))
        let panel = panel ?? FullscreenSubtitlePanel(frame: frame)
        panel.contentView = NSHostingView(rootView: view)
        panel.allowedMinY = FullscreenSubtitleRule.frame(on: screen, bottomGap: FullscreenSubtitleRule.bottomGapRange.lowerBound).minY
            ... FullscreenSubtitleRule.frame(on: screen, bottomGap: FullscreenSubtitleRule.bottomGapRange.upperBound).minY
        panel.onDragged = { [weak self] minY in self?.dragged(to: minY, on: screen) }
        panel.onScaled = { [weak self] factor in self?.scaled(by: factor) }
        panel.setFrame(frame, display: false)
        self.panel = panel
        present(panel)
    }
}
