import AppKit
import MyNotchCore
import Observation

/// Creates one notch per screen, keeps them in sync with displays, settings and fullscreen state.
public final class ScreenManager {
    private let registry: ModuleRegistry
    private let activities: ActivityCenter
    private let settings: SettingsStore
    private let scheduler: any Scheduler
    private let interface: NotchInterface
    /// The accent and look every notch is drawn with. It also keeps the text tokens in step with the look (`NotchLookState`).
    // Temporary (U3g): the candidates for "Trong vắt" are read from the defaults once, when the app makes its theme.
    private lazy var theme = NotchTheme(settings: settings, lookState: .shared, clearRecipe: NotchClearRecipeSwitch(reading: .standard))
    private var controllers: [String: NotchWindowController] = [:]
    private var fullscreenDisplays: Set<CGDirectDisplayID> = []
    /// The display the user is working on, for the display mode that follows them.
    private lazy var activeDisplay = ActiveDisplay(scheduler: scheduler) { [weak self] in self?.activeDisplayChanged() }
    /// Refreshed on every screen sync so pointer routing never queries `NSScreen.screens` per event.
    private var screenFrames: [(displayID: CGDirectDisplayID, frame: CGRect)] = []
    private var observers: [NSObjectProtocol] = []
    private lazy var hoverTracker = NotchHoverTracker(
        onMove: { [weak self] point, dragTypes in self?.pointerMoved(to: point, dragTypes: dragTypes) },
        onMouseDown: { [weak self] point in self?.mouseDown(at: point) }
    )
    private lazy var fullscreenDetector = FullscreenDetector(
        onChange: { [weak self] displays in
            if displays != self?.fullscreenDisplays { NotchLog.record("fullscreen displays=\(displays.sorted())") }
            self?.fullscreenDisplays = displays
            self?.applyVisibility()
        },
        onActivate: { [weak self] display in self?.activeDisplay.activated(on: display) }
    )

    /// Bumped when a display gains or loses its notch, so a reader of `isAnyNotchExpanded` also hears of a notch it has
    /// not looked at yet.
    private let controllerRevision = ControllerRevision()

    /// Whether any display's notch is open (a tab or a toast shows). Observable, for what only matters while someone can see the notch.
    public var isAnyNotchExpanded: Bool {
        _ = controllerRevision.count
        return controllers.values.contains { $0.model.state.isExpanded }
    }

    /// User toggle from the menu bar ("Show/Hide Notch").
    public var isHiddenByUser = false {
        didSet { applyVisibility() }
    }

    /// `interface` is where modules learn about the notches and the capture setting; the app uses the shared one.
    public init(
        registry: ModuleRegistry, activities: ActivityCenter, settings: SettingsStore, scheduler: any Scheduler,
        interface: NotchInterface = .shared
    ) {
        self.registry = registry
        self.activities = activities
        self.settings = settings
        self.scheduler = scheduler
        self.interface = interface
    }

    /// Starts observing displays, pointer and settings. Call once; later calls are ignored.
    public func start() {
        guard observers.isEmpty else { return }
        let app = NotificationCenter.default
        observers.append(app.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreens() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreens() }
        })
        // Before the notches exist and before the modules start, so none of them reads a stale setting.
        interface.follow(settings, theme: theme)
        syncScreens()
        hoverTracker.start()
        fullscreenDetector.start()
        observeSettings()
    }

    /// Visible controller for the screen under the pointer, else the visible one on the main screen, else any visible one.
    func activeController() -> NotchWindowController? {
        let point = NSEvent.mouseLocation
        if let uuid = NSScreen.screens.first(where: { $0.frame.containsMouseLocation(point) })?.displayUUID,
           let controller = controllers[uuid], controller.isVisible {
            return controller
        }
        let mainID = NSScreen.screens.first?.displayID
        let visible = controllers.values.filter(\.isVisible)
        return visible.first { $0.displayID == mainID } ?? visible.first
    }

    func allControllers() -> [NotchWindowController] { Array(controllers.values) }

    private func syncScreens() {
        let config = NotchLayoutConfig(settings: settings)
        var seen: Set<String> = []
        screenFrames = []
        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID, let displayID = screen.displayID else { continue }
            seen.insert(uuid)
            screenFrames.append((displayID, screen.frame))
            let descriptor = ScreenDescriptor(screen)
            if let controller = controllers[uuid] {
                controller.update(displayID: displayID, screen: descriptor, config: config)
            } else {
                controllerRevision.count += 1
                controllers[uuid] = NotchWindowController(
                    displayID: displayID, screen: descriptor, config: config, scheduler: scheduler,
                    registry: registry, activities: activities, delays: { [settings] in Self.delays(settings) },
                    captureHiding: { [settings] in settings.value(InterfaceSettings.hideFromCapture) },
                    swipesBetweenTabs: { [settings] in settings.value(InterfaceSettings.swipeBetweenTabs) },
                    swipeToOpen: { [settings] in
                        settings.value(InterfaceSettings.swipeToOpen) ? settings.value(InterfaceSettings.swipeSensitivity) : nil
                    },
                    theme: theme,
                    // Once for this notch: the glass is drawn as an active window's unless support turned that off.
                    drawsActiveGlass: NotchGlassSupport.drawsActiveGlass(.standard),
                    feel: { [interface] in interface.feel($0) }
                )
            }
        }
        for (uuid, controller) in controllers where !seen.contains(uuid) {
            controller.close()
            controllers[uuid] = nil
            controllerRevision.count += 1
        }
        activeDisplay.displaysChanged(screenFrames.map(\.displayID), pointerOn: DisplaySelection.display(at: NSEvent.mouseLocation, in: screenFrames))
        applyVisibility()
    }

    private func activeDisplayChanged() {
        NotchLog.record("active display -> \(activeDisplay.current.map(String.init) ?? "-")")
        if settings.value(InterfaceSettings.displayMode) == .cursor { applyVisibility() }
    }

    private func applyVisibility() {
        let mode = settings.value(InterfaceSettings.displayMode)
        let hideInFullscreen = settings.value(InterfaceSettings.hideInFullscreen)
        let shownByMode = DisplaySelection.shown(
            mode: mode, displays: NSScreen.screens.compactMap(\.displayID), active: activeDisplay.current
        )
        for controller in controllers.values {
            let id = controller.displayID
            let allowedByMode = shownByMode.contains(id)
            let hiddenByFullscreen = hideInFullscreen && fullscreenDisplays.contains(id)
            let visible = allowedByMode && !isHiddenByUser && !hiddenByFullscreen
            if visible != controller.isVisible {
                NotchLog.record(
                    "visibility display=\(id) -> \(visible) mode=\(mode) allowedByMode=\(allowedByMode) "
                        + "hiddenByUser=\(isHiddenByUser) hiddenByFullscreen=\(hiddenByFullscreen)"
                )
            }
            controller.setVisible(visible)
        }
        interface.notches = NotchInterface.visibleNotches(among: controllers.values.map { ($0.display, $0.isVisible) })
    }

    private func pointerMoved(to point: CGPoint, dragTypes: [String]) {
        activeDisplay.pointerMoved(onto: DisplaySelection.display(at: point, in: screenFrames))
        controllers.values.forEach { $0.pointerMoved(to: point, dragTypes: dragTypes) }
    }

    private func mouseDown(at point: CGPoint) {
        controllers.values.forEach { $0.mouseDown(at: point) }
    }

    private func observeSettings() {
        Task { [weak self, settings] in
            for await _ in Observations({ NotchLayoutConfig(settings: settings) }) {
                self?.syncScreens()
            }
        }
        Task { [weak self, settings] in
            for await _ in Observations({ (settings.value(InterfaceSettings.displayMode), settings.value(InterfaceSettings.hideInFullscreen)) }) {
                self?.applyVisibility()
            }
        }
    }

    private static func delays(_ settings: SettingsStore) -> (open: Duration, close: Duration) {
        (.milliseconds(settings.value(InterfaceSettings.openDelayMs)), .milliseconds(settings.value(InterfaceSettings.closeDelayMs)))
    }
}

@Observable
private final class ControllerRevision {
    var count = 0
}
