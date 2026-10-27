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
    /// The screen this notch is on, by its display UUID: it shows the activities that are shown on that screen. Nil for every activity.
    var display: String?

    @Namespace private var glassNamespace
    /// With `tiles`: whether the tiles' views are in the tree. They are while the notch is open (or a toast covers its tab), and stay
    /// after it closes until they are back in the notch's body (`NotchTile`), where they are taken out, unseen, as the notch's own glass
    /// is under them by then.
    @State private var tilesInTree = false

    private var state: NotchState { model.displayState }

    /// The live activities as this screen has them: what is not shown on it is not there.
    private var feed: ScreenActivities { activities.screen(display) }

    /// What the notch is drawn on: black, the classic look's blur, or Liquid Glass.
    private var surface: NotchSurface { theme?.surface(for: state) ?? .solid }

    /// The open tab, or the tab a toast covers: a page, or the grid of the pages in "Khác".
    private var shownTab: NotchTab? {
        guard let id = state.shownTab(tabUnderToast: model.tabUnderToast) else { return nil }
        if id == NotchPages.moreID { return moreTab() }
        return registry.tabs.first { $0.id == id }
    }

    /// The "Khác" item of the tab bar, which is also the page that holds the grid of the pages in it; nil while it has none.
    private func moreTab() -> NotchTab? {
        let overflow = registry.overflowTabs
        guard registry.tabs.count > 1, !overflow.isEmpty else { return nil }
        return NotchTab(
            id: NotchPages.moreID, title: "Khác", systemImage: "ellipsis.circle",
            preferredHeight: MoreTabGrid.contentHeight(pageCount: overflow.count),
            content: AnyView(MoreTabGrid(pages: overflow) { [model] in model.open(tab: $0) })
        )
    }

    /// The tab bar: the pages on it, then "Khác" while it holds any. A page in "Khác" shows as that item selected, with the page's own icon
    /// on it, so the user knows where they are.
    @ViewBuilder private var tabBar: some View {
        let pages = registry.pages
        let tabs = registry.tabs
        let items = pages.items.compactMap { id in id == NotchPages.moreID ? moreTab() : tabs.first { $0.id == id } }
        let shown = shownTab
        let selection = pages.selection(of: shown?.id)
        TabBar(
            tabs: items, selected: selection.item,
            badges: selection.badge == nil ? [:] : [NotchPages.moreID: shown?.systemImage ?? ""]
        ) { [model] in model.open(tab: $0) }
    }

    private var contentHeight: CGFloat { registry.contentHeight(for: state, tabUnderToast: model.tabUnderToast) }

    /// The bubbles and the open list that hang off the collapsed notch; nothing in every other state.
    private var accessories: CompactAccessories {
        CompactAccessories(activities: feed, geometry: geometry, isListOpen: model.isListOpen, state: state)
    }

    /// The width the current activity's strip asked for (`View.notchStripWidth`), which the collapsed notch is as wide as, also while the
    /// list is open under it; 0 when it has no strip or has not asked.
    private var stripWidth: CGFloat { model.stripWidth(of: feed, on: geometry.kind) }

    /// A strip tells the notch the width it wants: kept for its activity, while the strip is the one on show. The strip leaving (the
    /// notch opening, the activity ending, the list opening) reports 0 on its way out, which is not a request.
    private func strip(reportsWidth width: CGFloat, _ accessories: CompactAccessories, bottom: CGFloat) {
        // A strip is under the notch while it is not the list's turn; a body is over its top row all the time.
        guard state == .compact, bottom > 0 || feed.currentHasBody, accessories.listRows == 0 || feed.currentHasBody,
              let id = feed.current?.id else { return }
        model.reportStripWidth(width, for: id)
    }

    /// How far the collapsed notch grows: for the open list, which takes the strip's place, else for the current
    /// activity's strip; 0 in every other state.
    private func bottomHeight(_ accessories: CompactAccessories) -> CGFloat {
        geometry.bottomHeight(for: state, strip: feed.stripHeight(on: geometry.kind), listRows: accessories.listRows)
    }

    /// Everything that moves the shape. The notch animates all of it with the one spring, so a strip or the list
    /// showing or hiding is a single height change, not a second animation next to the state's. The bubbles are not
    /// part of it: they come and go beside the notch without touching its shape.
    private struct Layout: Equatable {
        let state: NotchState
        let bottom: CGFloat
        /// The outline and the gap below the screen's top edge: a change of the virtual notch's style (notch or pill) springs like
        /// any other change of the shape, instead of jumping.
        let shape: NotchShape
        let gap: CGFloat
        /// A strip that wants a wider or narrower notch moves the shape's width with the same spring.
        let width: CGFloat
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
        let slots = surface.isLiquidGlass && state == .compact ? ActivitySlot.bubbles(of: feed, capacity: geometry.bubbleCapacity) : []
        return NotchGlassPlan(
            surface: surface, bubbleIDs: slots.map(\.id), accent: theme?.accent ?? NotchTokens.accent, style: style, isOpen: isOpen
        )
    }

    var body: some View {
        let accessories = accessories
        let bottom = bottomHeight(accessories)
        let size = geometry.shapeSize(
            for: state, contentHeight: contentHeight, bottomHeight: bottom, tabCount: registry.tabs.count, stripWidth: stripWidth
        )
        let radii = geometry.cornerRadii(for: state)
        let _ = NotchPerf.count(.bodies)
        let _ = NotchLog.record(
            "body display=\(state.logDescription) size=\(size.width)x\(size.height) strip=\(feed.stripHeight(on: geometry.kind)) "
                + "bottom=\(bottom) bubbles=\(accessories.bubbles) list=\(accessories.listRows) shownTab=\(shownTab?.id.rawValue ?? "-")"
        )
        let shape = geometry.shape(for: state)
        let accent = theme?.accent ?? NotchTokens.accent
        let surface = surface
        let plan = glassPlan
        let layout = Layout(state: state, bottom: bottom, shape: shape, gap: geometry.topGap, width: size.width)
        NotchGlassFamily(plan) {
            ZStack(alignment: .top) {
                if let tiles = plan.tiles {
                    tilesNotch(plan: plan, tiles: tiles, size: size, radii: radii, accessories: accessories, layout: layout)
                } else {
                    NotchBackdrop(surface: surface, bodyHeight: backdropBodyHeight, veil: plan.veil)
                        .overlay(alignment: .top) {
                            content(accessories)
                                .padding(.horizontal, radii.top)
                                .environment(\.notch, NotchHandle(model: model))
                        }
                        .clipShape(shape)
                        .frame(width: size.width, height: size.height)
                        // Above the animation below, so the glass takes its shape and size from the same spring as the notch.
                        .notchGlass(plan.notch, in: shape, namespace: glassNamespace)
                        .background { if plan.blursUnder && plan.panelHasGlass { shape.fill(NotchGlassPlan.blurMaterial) } }
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
            // The floating pill's gap below the screen's top edge: layout, not an offset, so the glass is placed from it, and it springs
            // when the style changes. Nothing for the notch, which sticks to the edge.
            .padding(.top, geometry.topGap)
            .animation(NotchTokens.spring, value: geometry.topGap)
        }
        .overlay(alignment: .top) { gapVeil }
        .onPreferenceChange(NotchStripWidthKey.self) { strip(reportsWidth: $0, accessories, bottom: bottom) }
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

    /// How much of the top of the notch is the solid black of the cutout's own body under the classic blur: all of the body on a hardware
    /// notch, which has to join the cutout, and none on a display without one (a notch or a pill there has no cutout to join, and the tab
    /// page starts near its top).
    private var backdropBodyHeight: CGFloat { geometry.kind == .hardware ? geometry.notchSize.height : 0 }

    /// While the pill is open, the gap above it: faint enough that no one can see it, but not transparent, because a window lets a click
    /// on a fully transparent pixel through to what is behind (the menu bar), and the pointer there counts as being on the notch
    /// (`NotchGeometry.hitRect` reaches up through the gap). As wide as the open pill; nothing for the notch, or when the pill is
    /// collapsed (the pill itself takes the click).
    @ViewBuilder private var gapVeil: some View {
        if geometry.isPill && state.isExpanded {
            Color.black.opacity(NotchGlassPlan.hitOpacity).frame(width: geometry.shapeSize(for: .open(nil)).width, height: geometry.topGap)
        }
    }

    /// The drag targeting the notch reports: only the end of a drag is forwarded.
    private var dropTargeting: Binding<Bool> {
        Binding(get: { model.isDragging }, set: { if !$0 { model.setDragging(false) } })
    }

    /// The notch with `tiles`. Layers in one wrapper, all in the family's container so their glass blends and morphs, in this order, bottom
    /// to top:
    /// * the notch's **hit layer**, as big as the open notch whatever is drawn in it: it holds the faint veil that keeps the gaps between
    ///   the tiles part of the window, and it sizes the wrapper;
    /// * the tab bar's **capsule** and the content's **tile**, which are not inside the notch's shape, so nothing clips their glass: they
    ///   are in the tree from the moment the notch opens (or a toast covers a tab), start as the collapsed notch's body and spring from
    ///   there to where the tab page puts them (`NotchTilesLayout`), and when the notch closes they spring back, as glass the whole way,
    ///   and are taken out when they are back (`NotchTile`). Their content is laid out at its final size and clipped by the tile's
    ///   own shape, and fades in;
    /// * the notch's **own glass and content**, in the tree whenever the notch is not open: the collapsed notch's strip and a toast's
    ///   content are inside the view that carries the glass, which is what draws them above it (content outside it is under the
    ///   container's glass and comes out blurred). It is put in at the first frame of the close with its glass at once and as big as the
    ///   notch is, with the tiles still on their way back into it; the tiles and it are glass of one layer, so their shapes blend into one
    ///   as they meet, and the strip's text is above all of it. It is taken out the moment the notch opens, as the tiles take its place.
    ///
    /// The wrapper, whose size is the open notch's, carries the one hit shape, the one tap and the one drop target, as the slab's view
    /// does: SwiftUI delivers a gesture to the hit view and its ancestors, and the strip, the toast and the tab are all its descendants,
    /// and it targets one drop view at a time, so with a target on each of the layers a drag across the gap and a tile would report
    /// "not targeted" on every crossing and end drag mode in the middle of it.
    @ViewBuilder private func tilesNotch(
        plan: NotchGlassPlan, tiles: NotchGlassPlan.Tiles, size: CGSize, radii: (top: CGFloat, bottom: CGFloat),
        accessories: CompactAccessories, layout: Layout
    ) -> some View {
        let fullShape = geometry.shape(for: state)
        // The collapsed notch this one came from, and will go back to.
        let collapsed: NotchState = model.hasActivity ? .compact : .closed
        let collapsedRadii = geometry.cornerRadii(for: collapsed)
        let collapsedSize = collapsedSize(collapsed)
        let showsTabs = isOpen || model.tabUnderToast != nil
        let openRadii = geometry.cornerRadii(for: .open(nil))
        let final = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: contentHeight, tabCount: registry.tabs.count),
            topInset: geometry.openTopInset,
            topRadius: openRadii.top, tabCount: registry.tabs.count, bar: geometry.tabBarCapsule(tabCount: registry.tabs.count),
            items: registry.pages.items.count
        )
        let rest = NotchTilesLayout.rest(collapsedSize: collapsedSize, topRadius: collapsedRadii.top, hasTabBar: final.tabBar != nil)
        let inner = CGSize(
            width: final.content.size.width - 2 * NotchGlassPlan.tilePadding, height: final.content.size.height - 2 * NotchGlassPlan.tilePadding
        )

        ZStack(alignment: .top) {
            NotchBackdrop(surface: surface, bodyHeight: backdropBodyHeight, veil: plan.veil)
                .clipShape(fullShape)
                .frame(width: size.width, height: size.height)
                .animation(NotchTokens.spring, value: layout)

            if showsTabs || tilesInTree {
                if registry.tabs.count >= 2, let bar = final.tabBar {
                    tile(
                        rest: rest.tabBar ?? bar, final: bar, glass: tiles.tabBar, shape: Capsule(), restShape: Capsule(), showsTabs: showsTabs,
                        blurs: plan.blursUnder, atRest: tileIsBack
                    ) {
                        tabBar
                            .frame(width: TabBarMetrics.width(count: registry.pages.items.count), height: TabBarMetrics.iconSize.height)
                            // Centred in the capsule, which on a pill is as tall as the pill.
                            .padding(.top, (bar.size.height - TabBarMetrics.iconSize.height) / 2)
                    }
                }
                tile(
                    rest: rest.content, final: final.content, glass: tiles.content,
                    shape: RoundedRectangle(cornerRadius: concentricTileRadius, style: .continuous),
                    restShape: RoundedRectangle(cornerRadius: restTileRadius, style: .continuous), showsTabs: showsTabs,
                    blurs: plan.blursUnder, atRest: tileIsBack
                ) {
                    openContent
                        .frame(width: max(inner.width, 0), height: max(inner.height, 0))
                        .padding(.top, NotchGlassPlan.tilePadding)
                }
            }

            // Not in the tree while the notch is open (its glass would be a pill over the tiles' top), and in it from the moment the
            // notch closes, as real glass from its first frame, with the tiles still coming back into it.
            if !isOpen {
                Color.clear
                    .overlay(alignment: .top) {
                        content(accessories)
                            .padding(.horizontal, radii.top)
                            .environment(\.notch, NotchHandle(model: model))
                    }
                    .clipShape(fullShape)
                    .frame(width: size.width, height: size.height)
                    .notchGlass(plan.notch, in: fullShape, namespace: glassNamespace)
                    // No morph from a neighbour's shape: the glass is there at once and as big as the notch is, with the tiles still
                    // coming back into it.
                    .glassEffectTransition(.identity)
                    .background { if plan.blursUnder && plan.panelHasGlass { fullShape.fill(NotchGlassPlan.blurMaterial) } }
                    .animation(NotchTokens.spring, value: layout)
            }
        }
        .onChange(of: showsTabs, initial: true) { if showsTabs { tilesInTree = true } }
        .contentShape(fullShape)
        // Once open, taps belong to the tab content; the root tap only opens the notch.
        .gesture(TapGesture().onEnded { model.click() }, including: isOpen ? .subviews : .all)
        .onDrop(of: allDropTypes, isTargeted: dropTargeting) { providers in drop(providers) }
    }

    /// The size of the collapsed notch in `collapsed` that the tiles come out of and go back into: with a strip, the pill is as wide as the
    /// strip made it, and its body (the top row, which the tiles start as) with it.
    private func collapsedSize(_ collapsed: NotchState) -> CGSize {
        var size = geometry.shapeSize(for: collapsed)
        if collapsed == .compact { size.width = geometry.compactWidth(stripWidth: stripWidth) }
        return size
    }

    /// One tile: see `NotchTile`. Its content is laid out at the size it has when the notch is open, and is there while the tab is.
    private func tile<S: Shape, Content: View>(
        rest: NotchTilesLayout.Tile, final: NotchTilesLayout.Tile, glass: NotchGlassPlan.Shape, shape: S, restShape: S, showsTabs: Bool,
        blurs: Bool, atRest: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) -> some View {
        NotchTile(
            rest: rest, final: final, glass: glass, shape: shape, restShape: restShape, showsTabs: showsTabs, blurs: blurs, isOpen: isOpen,
            phase: isOpen ? .open : (showsTabs ? .covered : .closing), atRest: atRest,
            handle: NotchHandle(model: model), namespace: glassNamespace, content: content()
        )
    }

    /// A closing tile is back in the notch's body: with no tab and no toast, the tiles leave the tree (the last one to arrive does).
    private func tileIsBack() {
        if !isOpen && model.tabUnderToast == nil { tilesInTree = false }
    }

    /// The bubbles of the other live activities, beside the collapsed notch only. They appear and go with the pill's
    /// own content, and individually (and when they reorder) with the notch's spring; none of it touches the shape.
    @ViewBuilder private var bubbles: some View {
        if state == .compact {
            ActivityBubbles(
                slots: ActivitySlot.bubbles(of: feed, capacity: geometry.bubbleCapacity),
                geometry: geometry, stripWidth: stripWidth, iconScale: geometry.collapsedContentScale, label: label(for:), activate: activate
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
            if let entry = feed.current {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        entry.activity.leading.frame(width: geometry.config.compactSideWidth).scaled(geometry.collapsedContentScale)
                        Spacer(minLength: geometry.notchSize.width)
                        entry.activity.trailing.frame(width: geometry.config.compactSideWidth).scaled(geometry.collapsedContentScale)
                    }
                    .frame(height: geometry.notchSize.height)
                    // Both are laid out at their final height at once and revealed by the growing shape's clip, so the text
                    // never re-flows while the spring runs; they fade like the rest of the pill's content. The list takes
                    // the strip's place while it is open.
                    if accessories.listRows > 0 {
                        ActivityList(
                            rows: ActivitySlot.listRows(of: feed, capacity: NotchGeometry.maxListRows),
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
                // An overlay, so that an activity without a body lays the notch out exactly as it was. Not scaled with the sides: the notch
                // draws them bigger on a tall pill, and a body is made of pixels.
                .overlay(alignment: .top) {
                    if let body = entry.activity.body {
                        body
                            .frame(maxWidth: .infinity)
                            .frame(height: geometry.notchSize.height)
                            .notchLogLifecycle("body")
                    }
                }
                .environment(\.notchGeometry, geometry)
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
                tabBar.padding(.bottom, NotchTilesLayout.slabTabBarSpacing)
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

    /// The corner radius of the content's tile in the collapsed notch's body, which it springs from and back to: the radius of that
    /// body's own corners. On a notch that is 10, which is also the tile's radius when open (the same as before the pill); a pill's body is
    /// a capsule, half its height, and a tile with a smaller radius would stick out past the capsule's ends.
    private var restTileRadius: CGFloat { geometry.cornerRadii(for: .closed).bottom }

    private func expanded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.openTopInset)
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

/// How far a tile is from its body to its final rect, 0 to 1, as it is drawn: the spring that moves the tile runs this too (it is
/// the tile's own animatable data, which SwiftUI interpolates in the same transaction as the tile's frame), so it is the animated
/// value that a layout reading (`onGeometryChange`, which reports the target) cannot give. While `isClosing`, it tells `atRest` the
/// moment the tile is back in the body (`NotchTilesLayout.backWithin`), and every frame after.
private struct TileProgress: View, Animatable {
    var progress: Double
    let isClosing: Bool
    let atRest: () -> Void

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        if isClosing && progress <= Double(NotchTilesLayout.backWithin) {
            // Not in the middle of a render: the notch changes its tree in answer.
            let atRest = atRest
            DispatchQueue.main.async { atRest() }
        }
        return Color.clear
    }
}

/// The material under a tile's glass. On the way back into the notch it fades with the tile's progress, so that it is gone by the time the
/// tile is inside the notch's own glass, which has a material under it too: two of them, one over the other, would be a darker, more
/// saturated patch where the tile and the notch meet.
private struct TileMaterial<S: Shape>: View, Animatable {
    var progress: Double
    let isClosing: Bool
    let shape: S

    /// How far along the way out the tile is when its material is whole again, on the way back it is gone at 0.
    static var fullFrom: Double { 1 / 3 }

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        shape.fill(NotchGlassPlan.blurMaterial).opacity(isClosing ? min(max(progress / Self.fullFrom, 0), 1) : 1)
    }
}

/// One tile of the open notch (the tab bar's capsule, the content's tile): its glass in `shape`, at the size and the distance from the
/// top that the notch is in, with `content` inside, laid out at the size it has when the notch is open, clipped by the tile's own shape
/// and faded in while the tab is there.
///
/// The tile is in the tree from the moment the notch opens, at the notch's body (`rest`), and goes to `final`; from the moment it closes
/// it goes back, and when it is there it tells (`atRest`) and the notch takes it out of the tree. The frame and the padding are layout,
/// so they spring with the notch (the notch's own spring, both ways). Its glass is real the whole time, so that on the way back it
/// is a shape of the same container as the notch's own glass, which is there from the first frame of the close, and the two blend
/// into one; it is not glass while a toast covers the tab (the tab and its state stay), which is the one time it is `Glass.identity`.
private struct NotchTile<S: Shape, Content: View>: View {
    let rest: NotchTilesLayout.Tile
    let final: NotchTilesLayout.Tile
    let glass: NotchGlassPlan.Shape
    /// The tile's shape when it is open, and in the collapsed notch's body (the same, but for the content tile on a pill).
    let shape: S
    let restShape: S
    let showsTabs: Bool
    /// Whether a material is drawn under the tile's glass (`NotchGlassPlan.blursUnder`).
    let blurs: Bool
    let isOpen: Bool
    let phase: NotchTilesLayout.Phase
    let atRest: () -> Void
    let handle: NotchHandle
    let namespace: Namespace.ID
    let content: Content
    /// False in the tile's first frame, so that it starts in the notch's body and not at its final rect when it is made as the notch
    /// opens.
    @State private var appeared = false
    /// Whether the tile has had glass since the notch last opened: one that closes from under a toast never had it (it is not made glass
    /// to go back), and one that closes from open keeps it all the way.
    @State private var wasGlass = false

    var body: some View {
        let target = showsTabs && appeared ? final : rest
        let outline = target == final ? shape : restShape
        Color.clear
            .overlay(alignment: .top) {
                if showsTabs {
                    content
                        .environment(\.notch, handle)
                        .opacity(isOpen ? 1 : 0)
                        .allowsHitTesting(isOpen)
                        .accessibilityHidden(!isOpen)
                        .animation(NotchTokens.swap, value: isOpen)
                        .transition(.asymmetric(insertion: .opacity.animation(NotchTokens.enter), removal: .opacity.animation(NotchTokens.leave)))
                }
            }
            .clipShape(outline)
            .frame(width: target.size.width, height: target.size.height)
            // Late by the glass's lag behind the layout, so the tile is taken out when its glass, not only its frame, is back.
            .background {
                TileProgress(progress: target == final ? 1 : 0, isClosing: phase == .closing, atRest: atRest)
                    .animation(NotchTokens.spring.delay(NotchGlassPlan.glassLag), value: target)
            }
            .notchGlass(hasGlass ? glass : NotchGlassPlan.Shape(id: glass.id, glass: .identity), in: outline, namespace: namespace)
            .background {
                if blurs && hasGlass { TileMaterial(progress: target == final ? 1 : 0, isClosing: phase == .closing, shape: outline) }
            }
            .padding(.top, target.top)
            .animation(NotchTokens.spring, value: target)
            .onAppear { appeared = true }
            .onChange(of: phase, initial: true) { if phase == .open { wasGlass = true } else if phase == .covered { wasGlass = false } }
    }

    /// Glass while the notch is open, and on the way back if it was glass when it closed; not while a toast covers the tab.
    private var hasGlass: Bool { phase == .open || (phase == .closing && wasGlass) }
}
