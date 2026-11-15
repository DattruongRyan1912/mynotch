import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// The bar's window: borderless, never key and never activating, so a click on an item does not take the keyboard from the app in
/// front. Esc and a click elsewhere are heard by monitors (`MenuBarItemsBarController`), not by the window.
final class MenuBarItemsBarPanel: NSPanel {
    private var follower: CaptureHidingFollower?
    private var glass: ActiveGlassFollower?

    init(interface: NotchInterface = .shared) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the apps' windows and below the notch's panel and the menus that open from the status items.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        // NSPanel hides on deactivate by default; the app is hardly ever active while the bar is up.
        hidesOnDeactivate = false
        canHide = false
        animationBehavior = .none
        // The app is never active, so the items' tooltips must be allowed while inactive.
        allowsToolTipsWhenApplicationIsInactive = true
        // Like the black menu bar: out of recordings when the user keeps MyNotch's windows out of them while the notch is closed.
        follower = CaptureHidingFollower(self, as: .compact, interface: interface)
        // Never key, so without this the glass would be the subdued one, without the notch's lensing and rim.
        glass = ActiveGlassFollower(self, interface: interface)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func close() {
        follower?.stop()
        follower = nil
        glass?.stop()
        glass = nil
        super.close()
    }
}

/// Accepts the first click although the app is not active, which is every click on the bar.
final class MenuBarItemsBarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The app icons of the items, looked up once each while the bar is open.
final class MenuBarAppIcons {
    private var icons: [Int32: NSImage] = [:]

    func icon(for item: MenuBarItem) -> NSImage {
        if let cached = icons[item.pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: item.pid)?.icon.map(Self.fromLargeSize)
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: item.ownerName) ?? NSImage()
        icons[item.pid] = icon
        return icon
    }

    /// Only the icon's smallest size of at least 64 pixels, which the bar scales down. At the bar's size a 1x display would pick the
    /// 18 or 24 pixel size, which some apps ship broken (Docker's are noise).
    private static func fromLargeSize(_ icon: NSImage) -> NSImage {
        let large = icon.representations.filter { $0.pixelsWide >= 64 }.min { $0.pixelsWide < $1.pixelsWide }
        guard let large, let cgImage = large.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return icon }
        return NSImage(cgImage: cgImage, size: NSSize(width: 64, height: 64))
    }
}

/// Whether the bar is drawn out or folded into its right end, by the MyNotch icon: the controller sets it, the view animates it.
@Observable
final class MenuBarItemsBarPresence {
    var isShown = false
}

/// What the bar draws: the row of items, or a message when there is nothing to show yet, nothing to list or no permission to list it.
/// It unfolds from its right end with the notch's spring once there is something to show, and folds back the same way.
struct MenuBarItemsBarView: View {
    let bar: MenuBarItemsBar
    let interface: NotchInterface
    let icons: MenuBarAppIcons
    let presence: MenuBarItemsBarPresence
    let grantAccessibility: () -> Void

    /// How much of its size the folded bar keeps, so it grows out of a pill rather than out of nothing.
    private static let foldedScale: CGFloat = 0.6

    var body: some View {
        let isShown = presence.isShown && bar.phase != .loading
        GeometryReader { proxy in
            MenuBarItemsBarContent(bar: bar, icons: icons, grantAccessibility: grantAccessibility)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .opacity(isShown ? 1 : 0)
                // The content keeps its full width and the surface, which clips it, grows over it from the right.
                .frame(width: isShown ? proxy.size.width : proxy.size.height, alignment: .trailing)
                .tint(interface.accent)
                // The notch's own surface (black or glass, as the user chose), so the bar reads as part of it.
                .notchSurface(in: RoundedRectangle(cornerRadius: MenuBarItemsBarMetrics.cornerRadius, style: .continuous), of: interface)
                .scaleEffect(isShown ? 1 : Self.foldedScale, anchor: .trailing)
                .opacity(isShown ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .animation(NotchTokens.spring, value: isShown)
    }
}

/// The content itself, which reads the surface from its environment so its text is readable on black and on glass.
private struct MenuBarItemsBarContent: View {
    let bar: MenuBarItemsBar
    let icons: MenuBarAppIcons
    let grantAccessibility: () -> Void

    @Environment(\.notchSurface) private var surface

    var body: some View {
        switch bar.phase {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsAccessibility:
            HStack(spacing: 10) {
                Text("Cần quyền Trợ năng để xem icon ẩn.")
                    .font(.callout)
                    .foregroundStyle(surface.primaryStyle)
                    .lineLimit(2)
                Button("Cấp quyền", action: grantAccessibility)
            }
            .padding(.horizontal, MenuBarItemsBarMetrics.padding + 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready where bar.entries.isEmpty:
            Text("Không có icon nào đang bị ẩn.")
                .font(.callout)
                .foregroundStyle(surface.secondaryStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MenuBarItemsBarMetrics.spacing) {
                    ForEach(bar.entries) { entry in
                        MenuBarItemButton(
                            entry: entry, icon: icons.icon(for: entry.item),
                            choose: { secondary in bar.choose(entry.id, secondary: secondary) }
                        )
                    }
                }
                .padding(.horizontal, MenuBarItemsBarMetrics.padding)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct MenuBarItemButton: View {
    let entry: MenuBarBarEntry
    let icon: NSImage
    let choose: (_ secondary: Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        look
            .frame(width: MenuBarItemsBarMetrics.iconCellWidth)
            .frame(maxHeight: .infinity)
            .background(isHovered ? NotchTokens.fill(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHovered = $0 }
            .help(entry.item.toolTip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.item.toolTip)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { choose(false) }
            .accessibilityAction(named: "Mở menu") { choose(true) }
            .overlay { MenuBarItemClickCatcher(onClick: choose) }
    }

    /// The app's own icon: sharp at any scale, where a capture of the item is only as sharp as the display it is on.
    private var look: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: MenuBarItemsBarMetrics.iconSize, height: MenuBarItemsBarMetrics.iconSize)
    }
}

/// A click and a right-click on an item, which SwiftUI cannot tell apart. A control-click is the right-click of a trackpad.
private struct MenuBarItemClickCatcher: NSViewRepresentable {
    let onClick: (_ secondary: Bool) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.onClick = onClick }

    final class CatcherView: NSView {
        var onClick: ((Bool) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Without these the view would not be sent the matching mouse-ups.
        override func mouseDown(with event: NSEvent) {}

        override func rightMouseDown(with event: NSEvent) {}

        override func mouseUp(with event: NSEvent) {
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            onClick?(event.modifierFlags.contains(.control))
        }

        override func rightMouseUp(with event: NSEvent) {
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            onClick?(true)
        }
    }
}
