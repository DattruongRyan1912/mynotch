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
    /// The debug switches of the glass look (U3c), which the window controller read from the defaults once. Today's behaviour when
    /// left out.
    var switches: NotchGlassSwitches = .default

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
        // The bubbles are only drawn, and so only planned, beside the collapsed notch.
        let slots = surface.isLiquidGlass && state == .compact ? ActivitySlot.bubbles(of: activities, capacity: geometry.bubbleCapacity) : []
        let plan = NotchGlassPlan(surface: surface, bubbleIDs: slots.map(\.id), accent: accent, switches: switches)
        NotchGlassFamily(plan) {
            ZStack(alignment: .top) {
                NotchBackdrop(surface: surface, bodyHeight: geometry.notchSize.height, dim: plan.dim)
                    .overlay(alignment: .top) {
                        content(accessories)
                            .padding(.horizontal, radii.top)
                            .environment(\.notch, NotchHandle(model: model))
                            .notchContentScheme(plan.contentScheme)
                    }
                    .clipShape(shape)
                    .frame(width: size.width, height: size.height)
                    // The AppKit host's glass, if that is the one asked for; behind the shape, with its size and spring.
                    .notchAppKitGlass(plan.appKitNotch, topRadius: radii.top, bottomRadius: radii.bottom)
                    // Above the animation below, so the glass takes its shape and size from the same spring as the notch.
                    .notchGlass(plan.notch, in: shape, namespace: glassNamespace)
                    .contentShape(shape)
                    // Once open, taps belong to the tab content; the root tap only opens the notch.
                    .gesture(TapGesture().onEnded { model.click() }, including: isOpen ? .subviews : .all)
                    .animation(NotchTokens.spring, value: Layout(state: state, bottom: bottom))
                    // SwiftUI only reports targeting here. The window controller starts drag mode from the pointer, so
                    // only the end of a drag is forwarded, and the getter just reflects the model.
                    .onDrop(of: allDropTypes, isTargeted: Binding(get: { model.isDragging }, set: { if !$0 { model.setDragging(false) } })) { providers in
                        drop(providers)
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
        .environment(\.notchGlassSwitches, switches)
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
                    if isOpen || model.tabUnderToast != nil {
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
        // The cards of the tab bar, the sample strip and the tab are one inner family when they are glass (see `NotchGlassPlan`);
        // otherwise the group adds nothing.
        NotchCardGroup(spacing: NotchGlassPlan.cardContainerSpacing(surface: surface, switches: switches)) {
            VStack(spacing: 0) {
                if registry.tabs.count >= 2 {
                    TabBar(tabs: registry.tabs, selected: shownTab?.id) { model.open(tab: $0) }
                        .padding(.bottom, 6)
                }
                // Below the tab bar and above the tab, taking room from the tab: the notch does not grow for it.
                if switches.sample {
                    NotchSampleStrip(cardRadius: sampleCardRadius)
                }
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
        }
    }

    /// The sample card's radius: the open notch's bottom radius less the padding between the card and the notch's edge, so the
    /// card's corner is concentric with the notch's (24 - 14 = 10).
    private var sampleCardRadius: CGFloat {
        NotchCardPlan.concentricRadius(outer: geometry.cornerRadii(for: .open(nil)).bottom, inset: NotchTokens.padding)
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
