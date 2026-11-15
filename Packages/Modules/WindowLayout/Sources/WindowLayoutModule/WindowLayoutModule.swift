import MyNotchCore
import NotchUI
import SwiftUI
import os

/// Snaps a window into a layout when it is dragged onto the notch: while a window is dragged and the pointer comes near
/// the notch, the notch opens a row of layout tiles; letting go over a tile moves and resizes the window to that tile's
/// part of the display's visible area (Accessibility), and Esc cancels. Dragging windows is told from other drags by
/// watching the focused window move, which needs the Accessibility permission, so without it the module does nothing.
public final class WindowLayoutModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "windows",
        displayName: "Chia cửa sổ",
        systemImage: "rectangle.split.2x2",
        defaultEnabled: true,
        // Not required to start: the module idles until it is granted, which takes effect without a restart.
        optionalPermissions: [.accessibility],
        permissionReasons: [.accessibility: "Nhận ra cửa sổ bạn đang kéo và đặt nó vào ô bạn thả lên notch."],
        order: 950
    )

    /// How long the notch holds the tiles at most. They close with the drag, so this only bounds a drag that never ends.
    static let tilesLifetime = Duration.seconds(30)
    /// How long the notch shows the line about a window that did not fit its zone.
    static let noticeLifetime = Duration.seconds(4)

    private let events: any DragEventSource
    private let probe: any WindowProbe
    private let screens: () -> SnapScreens
    private let makePreview: () -> any SnapPreview
    private let interface: NotchInterface
    private var session: SnapSession?

    /// The module the app runs: the system's mouse monitors, Accessibility and the shared notch interface.
    public convenience init() {
        self.init(
            events: SystemDragEvents(), probe: SystemWindowProbe(), screens: SystemScreens.current,
            makePreview: { SnapPreviewOverlay() }, interface: .shared
        )
    }

    /// Tests pass fakes for everything that would reach the system.
    init(
        events: any DragEventSource, probe: any WindowProbe, screens: @escaping () -> SnapScreens,
        makePreview: @escaping () -> any SnapPreview, interface: NotchInterface
    ) {
        self.events = events
        self.probe = probe
        self.screens = screens
        self.makePreview = makePreview
        self.interface = interface
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        let settings = context.settings
        let keys = WindowLayoutKeys(settings)
        let permissions = context.permissions
        let presenter = context.presenter
        let interface = interface
        let logger = Log.logger(category: "window-layout")
        let session = SnapSession(
            environment: SnapSession.Environment(
                isTrusted: { permissions.status(of: .accessibility) == .granted },
                notches: { interface.notches },
                screens: screens,
                options: { keys.options(settings) },
                showTiles: { presenter.showToast($0, duration: Self.tilesLifetime) },
                hideTiles: { presenter.close() },
                feel: { interface.feel(.alignment) },
                log: { logger.notice("\($0, privacy: .public)") },
                notify: { presenter.showToast(AnyView(SnapNoticeView(text: $0)), duration: Self.noticeLifetime) }
            ),
            probe: probe, events: events, makePreview: makePreview, scheduler: context.scheduler
        )
        self.session = session
        events.start { [weak session] event in session?.handle(event) }
    }

    public func stop() async {
        events.stop()
        // Before the registry makes the presenter inert, so tiles open at this moment are closed with the notch.
        session?.stop()
        session = nil
    }

    public func makeTab() -> NotchTab? { nil }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(WindowLayoutSettingsView(settings: environment.settings, keys: WindowLayoutKeys(environment.settings)))
    }
}
