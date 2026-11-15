import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// Manages the native standalone Dashboard window for MyNotch.
/// Follows strict lifecycle: polls telemetry only while visible, releases resources when occluded/closed,
/// and balances macOS activation policy (.regular vs .accessory) with other titled windows.
@MainActor
final class DashboardWindowController: NSObject {
    private let registry: ModuleRegistry
    private let scheduler: any Scheduler
    private let openSettingsHandler: () -> Void
    private let telemetry: DashboardTelemetryCenter
    private let navigation = DashboardNavigationState()
    private var window: NSWindow?

    var isVisible: Bool { telemetry.isWindowVisible }

    init(
        registry: ModuleRegistry,
        scheduler: any Scheduler,
        openSettings: @escaping () -> Void
    ) {
        self.registry = registry
        self.scheduler = scheduler
        self.openSettingsHandler = openSettings
        self.telemetry = DashboardTelemetryCenter(registry: registry, scheduler: scheduler)
        super.init()

        NotificationCenter.default.addObserver(
            forName: DashboardThemeStore.themeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                let style = DashboardThemeStore.shared.style
                if style == .liquidGlass {
                    self?.window?.backgroundColor = .clear
                } else {
                    self?.window?.backgroundColor = NSColor(DashboardTheme.canvasBackground)
                }
                self?.window?.invalidateShadow()
            }
        }
    }

    /// Shows or brings the Dashboard window to the front.
    func show(tab: DashboardTab? = nil) {
        if let tab {
            navigation.selectedTab = tab
        }
        if window == nil {
            let root = DashboardRootView(
                telemetry: telemetry,
                registry: registry,
                nav: navigation,
                openSettings: openSettingsHandler
            )
            let hostingController = NSHostingController(rootView: root)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.contentViewController = hostingController
            win.title = "Bảng điều khiển MyNotch"
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.toolbarStyle = .unified
            win.appearance = NSAppearance(named: .aqua)
            let currentStyle = DashboardThemeStore.shared.style
            win.isOpaque = false
            win.backgroundColor = currentStyle == .liquidGlass ? .clear : NSColor(DashboardTheme.canvasBackground)
            win.isMovableByWindowBackground = true
            win.contentMinSize = NSSize(width: 880, height: 560)
            StandardWindowBehavior.apply(to: win, allowsNativeFullScreen: true)
            win.setContentSize(NSSize(width: 1080, height: 720))
            if !win.setFrameAutosaveName("MyNotch.DashboardWindow") || win.frame.width < 880 || win.frame.height < 560 {
                win.setContentSize(NSSize(width: 1080, height: 720))
                win.center()
            }
            win.isReleasedWhenClosed = false
            win.delegate = self
            self.window = win
        }

        if let win = window, (win.frame.width < 880 || win.frame.height < 560) {
            win.setContentSize(NSSize(width: 1080, height: 720))
            win.center()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        setWindowVisible(true)
        telemetry.refresh()
    }

    /// Toggles the Dashboard window visibility.
    func toggle() {
        if let window, window.isVisible, !window.isMiniaturized {
            window.performClose(nil)
        } else {
            show()
        }
    }

    #if DEBUG
    /// Captures the rendered raster image of the Dashboard window (Debug audit only).
    @discardableResult
    func captureSnapshot(to url: URL) -> Bool {
        guard let contentView = window?.contentView else { return false }
        let bounds = contentView.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return false }
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// Exports studio evidence into a designated sandboxed directory for verification and audits (Debug audit only).
    func exportEvidence(to directory: URL) {
        show(tab: .productivity)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        captureSnapshot(to: directory.appendingPathComponent("dashboard_productivity_clean_ui.png"))
        captureSnapshot(to: directory.appendingPathComponent("habit_studio_heatmap.png"))

        show(tab: .battery)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        captureSnapshot(to: directory.appendingPathComponent("dashboard_battery_studio.png"))

        show(tab: .todo)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        captureSnapshot(to: directory.appendingPathComponent("dashboard_todo_studio.png"))

        // Export snapshots for 3 themes on Overview tab
        show(tab: .overview)
        DashboardThemeStore.shared.setStyle(.softUI)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        captureSnapshot(to: directory.appendingPathComponent("dashboard_theme_soft_ui.png"))

        DashboardThemeStore.shared.setStyle(.liquidGlass)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        captureSnapshot(to: directory.appendingPathComponent("dashboard_theme_liquid_glass.png"))

        DashboardThemeStore.shared.setStyle(.stripeLight)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
        captureSnapshot(to: directory.appendingPathComponent("dashboard_theme_stripe_light.png"))

        DashboardThemeStore.shared.setStyle(.softUI)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    }
    #endif

    private func setWindowVisible(_ visible: Bool) {
        telemetry.setWindowVisible(visible)
    }
}

// MARK: - NSWindowDelegate

extension DashboardWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        telemetry.refresh()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        let isOccluded = window?.occlusionState.contains(.visible) != true
        setWindowVisible(!isOccluded)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        setWindowVisible(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        setWindowVisible(true)
        telemetry.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        setWindowVisible(false)
        let closing = notification.object as? NSWindow
        let otherTitledWindowVisible = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled)
        }
        if !otherTitledWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
