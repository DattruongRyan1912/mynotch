import AppKit
import MyNotchCore

/// Creates one notch per screen, keeps them in sync with displays, settings and fullscreen state.
public final class ScreenManager {
    private let registry: ModuleRegistry
    private let activities: ActivityCenter
    private let settings: SettingsStore
    private let scheduler: any Scheduler
    private var controllers: [String: NotchWindowController] = [:]
    private var fullscreenDisplays: Set<CGDirectDisplayID> = []
    private var cursorDisplay: CGDirectDisplayID?
    private var observers: [NSObjectProtocol] = []
    private lazy var hoverTracker = NotchHoverTracker { [weak self] point in self?.pointerMoved(to: point) }
    private lazy var fullscreenDetector = FullscreenDetector { [weak self] displays in
        self?.fullscreenDisplays = displays
        self?.applyVisibility()
    }

    /// User toggle from the menu bar ("Show/Hide Notch").
    public var isHiddenByUser = false {
        didSet { applyVisibility() }
    }

    public init(registry: ModuleRegistry, activities: ActivityCenter, settings: SettingsStore, scheduler: any Scheduler) {
        self.registry = registry
        self.activities = activities
        self.settings = settings
        self.scheduler = scheduler
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
        cursorDisplay = NSScreen.screens.first { $0.frame.containsMouseLocation(NSEvent.mouseLocation) }?.displayID
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
        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID, let displayID = screen.displayID else { continue }
            seen.insert(uuid)
            let descriptor = ScreenDescriptor(screen)
            if let controller = controllers[uuid] {
                controller.update(displayID: displayID, screen: descriptor, config: config)
            } else {
                controllers[uuid] = NotchWindowController(
                    displayID: displayID, screen: descriptor, config: config, scheduler: scheduler,
                    registry: registry, activities: activities, delays: { [settings] in Self.delays(settings) }
                )
            }
        }
        for (uuid, controller) in controllers where !seen.contains(uuid) {
            controller.close()
            controllers[uuid] = nil
        }
        applyVisibility()
    }

    private func applyVisibility() {
        let mode = settings.value(InterfaceSettings.displayMode)
        let hideInFullscreen = settings.value(InterfaceSettings.hideInFullscreen)
        let mainID = NSScreen.screens.first?.displayID
        for controller in controllers.values {
            let id = controller.displayID
            let allowedByMode = switch mode {
            case .all: true
            case .main: id == mainID
            case .cursor: id == (cursorDisplay ?? mainID)
            }
            let hiddenByFullscreen = hideInFullscreen && fullscreenDisplays.contains(id)
            controller.setVisible(allowedByMode && !isHiddenByUser && !hiddenByFullscreen)
        }
    }

    private func pointerMoved(to point: CGPoint) {
        let display = NSScreen.screens.first { $0.frame.containsMouseLocation(point) }?.displayID
        if display != cursorDisplay {
            cursorDisplay = display
            if settings.value(InterfaceSettings.displayMode) == .cursor { applyVisibility() }
        }
        controllers.values.forEach { $0.pointerMoved(to: point) }
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
