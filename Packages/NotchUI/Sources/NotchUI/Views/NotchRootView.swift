import MyNotchCore
import SwiftUI
import UniformTypeIdentifiers

/// Root SwiftUI view hosted in each notch panel.
struct NotchRootView: View {
    let model: NotchViewModel
    let activities: ActivityCenter
    let registry: ModuleRegistry
    let geometry: NotchGeometry
    /// The user's accent and glass; nothing is the notch's own purple and no glass.
    var theme: NotchTheme?

    @Namespace private var glassNamespace

    private var state: NotchState { model.displayState }

    /// What the notch is drawn on: black, the classic look's blur, or Liquid Glass.
    private var surface: NotchSurface { theme?.surface(for: state) ?? .solid }

    /// The open tab, or the tab a toast covers.
    private var shownTab: NotchTab? {
        guard let id = state.shownTab(tabUnderToast: model.tabUnderToast) else { return nil }
        return registry.tabs.first { $0.id == id }
    }

    private var contentHeight: CGFloat { registry.contentHeight(for: state, tabUnderToast: model.tabUnderToast) }

    /// The bubbles and the open list that hang off the collapsed notch; nothing in every other state.
    private var accessories: CompactAccessories {
        CompactAccessories(activities: activities, geometry: geometry, isListOpen: model.isListOpen, state: state)
    }

    /// How far the collapsed notch grows: for the open list, which takes the strip's place, else for the current
    /// activity's strip; 0 in every other state.
    private func bottomHeight(_ accessories: CompactAccessories) -> CGFloat {
        geometry.bottomHeight(for: state, strip: activities.stripHeight, listRows: accessories.listRows)
    }

    /// Everything that moves the shape. The notch animates all of it with the one spring, so a strip or the list
    /// showing or hiding is a single height change, not a second animation next to the state's. The bubbles are not
    /// part of it: they come and go beside the notch without touching its shape.
    private struct Layout: Equatable {
        let state: NotchState
        let bottom: CGFloat
    }

    /// What names an activity to a person and to VoiceOver: its summary, else its module's name.
    private func label(for entry: ActivityCenter.Entry) -> String {
        ActivityLabel.text(
            summary: entry.activity.summary,
            displayName: registry.modules.first { $0.descriptor.id == entry.module }?.descriptor.displayName,
            module: entry.module
        )
    }

    /// A bubble opens its module's tab; one that has none (or "+N") opens the list, which VoiceOver and the keyboard
    /// have no hover to open.
    private func activate(_ slot: ActivitySlot) {
        if case .activity(let entry) = slot, model.openTab(of: entry.module) { return }
        model.showList()
    }

    private var isOpen: Bool {
        if case .open = state { true } else { false }
    }

    private var allDropTypes: [UTType] {
        registry.tabs.reduce(into: []) { types, tab in types += tab.dropTypes.filter { !types.contains($0) } }
    }

    /// Hands the items to the shown tab when it accepts them, else to the first tab that does.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let types = providers.flatMap(\.registeredTypeIdentifiers)
        let target = DropRouting.tab(for: types, tabs: registry.tabs, preferring: shownTab?.id)
        return registry.tabs.first { $0.id == target }?.onDrop?(providers) ?? false
    }

    /// The user's two choices about the glass, read live.
    private var style: NotchGlassStyle { theme?.glassStyle ?? .default }

    /// Whether the open notch is made of tiles: that shape, on Liquid Glass.
    private var usesTiles: Bool { surface.isLiquidGlass && style.shape == .tiles }

    /// What glass the notch asks for in its state now: the bubbles beside the collapsed notch, and with `tiles` the capsule and the tile.
    private var glassPlan: NotchGlassPlan {
        let surface = surface
        // The bubbles are only drawn, and so only planned, beside the collapsed notch.
        let slots = surface.isLiquidGlass && state == .compact ? ActivitySlot.bubbles(of: activities, capacity: geometry.bubbleCapacity) : []
        return NotchGlassPlan(
            surface: surface, bubbleIDs: slots.map(\.id), accent: theme?.accent ?? NotchTokens.accent, style: style, isOpen: isOpen
        )
    }

    var body: some View {
        let accessories = accessories
        let bottom = bottomHeight(accessories)
        let size = geometry.shapeSize(for: state, contentHeight: contentHeight, bottomHeight: bottom)
        let radii = geometry.cornerRadii(for: state)
        let _ = NotchPerf.count(.bodies)
        let _ = NotchLog.record(
            "body display=\(state.logDescription) size=\(size.width)x\(size.height) strip=\(activities.stripHeight) "
                + "bottom=\(bottom) bubbles=\(accessories.bubbles) list=\(accessories.listRows) shownTab=\(shownTab?.id.rawValue ?? "-")"
        )
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        let accent = theme?.accent ?? NotchTokens.accent
        let surface = surface
        let plan = glassPlan
        let layout = Layout(state: state, bottom: bottom)
        NotchGlassFamily(plan) {
            ZStack(alignment: .top) {
                if let tiles = plan.tiles {
                    tilesNotch(plan: plan, tiles: tiles, size: size, radii: radii, accessories: accessories, layout: layout)
                } else {
                    NotchBackdrop(surface: surface, bodyHeight: geometry.notchSize.height, veil: plan.veil)
                        .overlay(alignment: .top) {
                            content(accessories)
                                .padding(.horizontal, radii.top)
                                .environment(\.notch, NotchHandle(model: model))
                        }
                        .clipShape(shape)
                        .frame(width: size.width, height: size.height)
                        // Above the animation below, so the glass takes its shape and size from the same spring as the notch.
                        .notchGlass(plan.notch, in: shape, namespace: glassNamespace)
                        .contentShape(shape)
                        // Once open, taps belong to the tab content; the root tap only opens the notch.
                        .gesture(TapGesture().onEnded { model.click() }, including: isOpen ? .subviews : .all)
                        .animation(NotchTokens.spring, value: layout)
                        // SwiftUI only reports targeting here. The window controller starts drag mode from the pointer, so
                        // only the end of a drag is forwarded, and the getter just reflects the model.
                        .onDrop(of: allDropTypes, isTargeted: dropTargeting) { providers in drop(providers) }
                }
                bubbles
            }
        }
        .environment(\.notchIsOnScreen, model.isOnScreen)
        // The accent for the notch's own controls and for a tab's marks, and the tint of the system controls in a tab.
        .environment(\.notchAccent, accent)
        .tint(accent)
        // What the notch is drawn on, for its own views' foreground. Nothing is forced on the content: on glass it keeps the
        // colour scheme the window has, which is the system's.
        .environment(\.notchSurface, surface)
        .environment(\.notchGlassNamespace, surface.isLiquidGlass ? glassNamespace : nil)
        .environment(\.notchGlassPlan, plan)
    }

    /// The drag targeting the notch reports: only the end of a drag is forwarded.
    private var dropTargeting: Binding<Bool> {
        Binding(get: { model.isDragging }, set: { if !$0 { model.setDragging(false) } })
    }

    /// The notch with `tiles`. Four layers in one wrapper, all in the family's container so their glass blends and morphs:
    /// * the notch's **hit layer**, as big as the open notch whatever is drawn in it: it holds the faint veil that keeps the gaps between
    ///   the tiles part of the window, and it sizes the wrapper;
    /// * the notch's **own glass and content**: the collapsed notch's strip and a toast's content are inside the view that carries
    ///   the glass, which is what draws them above it (content outside it is under the container's glass and comes out blurred). Its
    ///   glass is `Glass.identity` while the notch is open, and then it is only as big as the collapsed notch, so that it is already
    ///   the right size when it comes back and nothing of the open notch's size ever shows as glass on the way;
    /// * the tab bar's **capsule** and the content's **tile**, which are not inside the notch's shape, so nothing clips their glass: they
    ///   are the collapsed notch's body while the notch is not open, and spring from there to where the tab page puts them
    ///   (`NotchTilesLayout`), and back. Their content is laid out at its final size and clipped by the tile's own shape, and fades in.
    ///
    /// The wrapper, whose size is the open notch's, carries the one hit shape, the one tap and the one drop target, as the slab's view
    /// does: SwiftUI delivers a gesture to the hit view and its ancestors, and the strip, the toast and the tab are all its descendants,
    /// and it targets one drop view at a time, so with a target on each of the layers a drag across the gap and a tile would report
    /// "not targeted" on every crossing and end drag mode in the middle of it.
    @ViewBuilder private func tilesNotch(
        plan: NotchGlassPlan, tiles: NotchGlassPlan.Tiles, size: CGSize, radii: (top: CGFloat, bottom: CGFloat),
        accessories: CompactAccessories, layout: Layout
    ) -> some View {
        let fullShape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        // The collapsed notch this one came from, and will go back to.
        let collapsed: NotchState = model.hasActivity ? .compact : .closed
        let collapsedRadii = geometry.cornerRadii(for: collapsed)
        let collapsedSize = geometry.shapeSize(for: collapsed)
        let glassSize = isOpen ? collapsedSize : size
        let glassRadii = isOpen ? collapsedRadii : radii
        let glassShape = NotchShape(topRadius: glassRadii.top, bottomRadius: glassRadii.bottom)
        let showsTabs = isOpen || model.tabUnderToast != nil
        let openRadii = geometry.cornerRadii(for: .open(nil))
        let final = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: contentHeight), notchHeight: geometry.notchSize.height,
            topRadius: openRadii.top, tabCount: registry.tabs.count
        )
        let current = showsTabs
            ? final : NotchTilesLayout.rest(collapsedSize: collapsedSize, topRadius: collapsedRadii.top, hasTabBar: final.tabBar != nil)
        let inner = CGSize(
            width: final.content.size.width - 2 * NotchGlassPlan.tilePadding, height: final.content.size.height - 2 * NotchGlassPlan.tilePadding
        )

        ZStack(alignment: .top) {
            NotchBackdrop(surface: surface, bodyHeight: geometry.notchSize.height, veil: plan.veil)
                .clipShape(fullShape)
                .frame(width: size.width, height: size.height)
                .animation(NotchTokens.spring, value: layout)

            Color.clear
                .overlay(alignment: .top) {
                    content(accessories)
                        .padding(.horizontal, radii.top)
                        .environment(\.notch, NotchHandle(model: model))
                }
                .clipShape(glassShape)
                .frame(width: glassSize.width, height: glassSize.height)
                .notchGlass(plan.notch, in: glassShape, namespace: glassNamespace)
                .animation(NotchTokens.spring, value: layout)

            if registry.tabs.count >= 2, let bar = current.tabBar {
                tile(bar, glass: tiles.tabBar, shape: Capsule(), key: current, showsTabs: showsTabs) {
                    TabBar(tabs: registry.tabs, selected: shownTab?.id) { model.open(tab: $0) }
                        .frame(width: TabBarMetrics.width(count: registry.tabs.count), height: TabBarMetrics.iconSize.height)
                        .padding(.top, NotchGlassPlan.tabBarInset.height)
                }
            }
            tile(
                current.content, glass: tiles.content, shape: RoundedRectangle(cornerRadius: concentricTileRadius, style: .continuous),
                key: current, showsTabs: showsTabs
            ) {
                openContent
                    .frame(width: max(inner.width, 0), height: max(inner.height, 0))
                    .padding(.top, NotchGlassPlan.tilePadding)
            }
        }
        .contentShape(fullShape)
        // Once open, taps belong to the tab content; the root tap only opens the notch.
        .gesture(TapGesture().onEnded { model.click() }, including: isOpen ? .subviews : .all)
        .onDrop(of: allDropTypes, isTargeted: dropTargeting) { providers in drop(providers) }
    }

    /// One tile: its glass in `shape`, which is `tile`'s size and distance from the top, with `content` inside, laid out at the size it
    /// has when the notch is open, clipped by the tile's own shape and faded in while the tab is there. Frame and padding are layout,
    /// so the glass follows them as they spring; `key` is what the spring is keyed on, so a tab of another height moves it too.
    private func tile<S: Shape, Content: View>(
        _ tile: NotchTilesLayout.Tile, glass: NotchGlassPlan.Shape, shape: S, key: NotchTilesLayout, showsTabs: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Color.clear
            .overlay(alignment: .top) {
                if showsTabs {
                    content()
                        .environment(\.notch, NotchHandle(model: model))
                        .opacity(isOpen ? 1 : 0)
                        .allowsHitTesting(isOpen)
                        .accessibilityHidden(!isOpen)
                        .animation(NotchTokens.swap, value: isOpen)
                        .transition(.asymmetric(insertion: .opacity.animation(NotchTokens.enter), removal: .opacity.animation(NotchTokens.leave)))
                }
            }
            .clipShape(shape)
            .frame(width: tile.size.width, height: tile.size.height)
            .notchGlass(glass, in: shape, namespace: glassNamespace)
            .padding(.top, tile.top)
            .animation(NotchTokens.spring, value: key)
    }

    /// The bubbles of the other live activities, beside the collapsed notch only. They appear and go with the pill's
    /// own content, and individually (and when they reorder) with the notch's spring; none of it touches the shape.
    @ViewBuilder private var bubbles: some View {
        if state == .compact {
            ActivityBubbles(
                slots: ActivitySlot.bubbles(of: activities, capacity: geometry.bubbleCapacity),
                geometry: geometry, label: label(for:), activate: activate
            )
            .transition(.asymmetric(insertion: .opacity.animation(NotchTokens.enter), removal: .opacity.animation(NotchTokens.leave)))
            .notchLogLifecycle("bubbles")
        }
    }

    @ViewBuilder private func content(_ accessories: CompactAccessories) -> some View {
        switch state {
        case .closed:
            EmptyView()
        case .compact:
            if let entry = activities.current {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        entry.activity.leading.frame(width: geometry.config.compactSideWidth)
                        Spacer(minLength: geometry.notchSize.width)
                        entry.activity.trailing.frame(width: geometry.config.compactSideWidth)
                    }
                    .frame(height: geometry.notchSize.height)
                    // Both are laid out at their final height at once and revealed by the growing shape's clip, so the text
                    // never re-flows while the spring runs; they fade like the rest of the pill's content. The list takes
                    // the strip's place while it is open.
                    if accessories.listRows > 0 {
                        ActivityList(
                            rows: ActivitySlot.listRows(of: activities, capacity: NotchGeometry.maxListRows),
                            label: label(for:), hasTab: model.hasTab(of:), open: { model.openTab(of: $0) }
                        )
                        .frame(height: bottomHeight(accessories))
                        .padding(.horizontal, NotchTokens.stripPadding)
                        .transition(.asymmetric(insertion: .opacity.animation(NotchTokens.enter), removal: .opacity.animation(NotchTokens.leave)))
                        .notchLogLifecycle("list")
                    } else if bottomHeight(accessories) > 0, let bottom = entry.activity.bottom {
                        bottom
                            .frame(height: bottomHeight(accessories))
                            .padding(.horizontal, NotchTokens.stripPadding)
                            .transition(.asymmetric(insertion: .opacity.animation(NotchTokens.enter), removal: .opacity.animation(NotchTokens.leave)))
                            .notchLogLifecycle("strip")
                    }
                }
                .transition(.asymmetric(insertion: .opacity.animation(NotchTokens.enter), removal: .opacity.animation(NotchTokens.leave)))
                .notchLogLifecycle("compact")
            }
        case .open, .toast:
            // One branch for both, so a tab covered by a toast keeps its identity and its SwiftUI state
            // (search text, focus, scroll position): it stays alive underneath, invisible and inert.
            expanded {
                ZStack {
                    // With `tiles` the tab bar and the tab are in the tiles, outside the notch's own shape.
                    if !usesTiles, isOpen || model.tabUnderToast != nil {
                        tabPage
                            .opacity(isOpen ? 1 : 0)
                            .allowsHitTesting(isOpen)
                            .accessibilityHidden(!isOpen)
                            .animation(NotchTokens.swap, value: isOpen)
                    }
                    if !isOpen {
                        model.toastContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity.animation(NotchTokens.swap))
                    }
                }
            }
        }
    }

    private var tabPage: some View {
        VStack(spacing: 0) {
            if registry.tabs.count >= 2 {
                TabBar(tabs: registry.tabs, selected: shownTab?.id) { model.open(tab: $0) }
                    .padding(.bottom, 6)
            }
            openContent
        }
    }

    @ViewBuilder private var openContent: some View {
        if let shownTab {
            shownTab.content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Esc while the tab has focus; the panel's cancelOperation covers the rest.
                .onExitCommand { model.close() }
                .notchLogLifecycle("tab \(shownTab.id.rawValue)")
                .id(shownTab.id)
                .transition(.opacity.animation(NotchTokens.swap))
        } else {
            Text("Chưa có module nào đang chạy")
                .foregroundStyle(surface.secondaryStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The corner radius of the content's tile: the open notch's bottom radius less the padding between the tile and the notch's
    /// edge, so the tile's corner is concentric with the notch's (24 - 14 = 10).
    private var concentricTileRadius: CGFloat {
        NotchGlassPlan.concentricRadius(outer: geometry.cornerRadii(for: .open(nil)).bottom, inset: NotchTokens.padding)
    }

    private func expanded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchSize.height)
            content()
        }
        .padding([.horizontal, .bottom], NotchTokens.padding)
        .notchLogLifecycle("expanded")
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(NotchTokens.enter),
            removal: .opacity.animation(NotchTokens.leave)
        ))
    }
}
