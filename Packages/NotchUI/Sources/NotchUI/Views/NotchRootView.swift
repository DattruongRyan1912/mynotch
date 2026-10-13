import MyNotchCore
import SwiftUI
import UniformTypeIdentifiers

/// Root SwiftUI view hosted in each notch panel.
struct NotchRootView: View {
    let model: NotchViewModel
    let activities: ActivityCenter
    let registry: ModuleRegistry
    let geometry: NotchGeometry

    private var state: NotchState { model.displayState }

    /// The open tab, or the tab a toast covers.
    private var shownTab: NotchTab? {
        guard let id = state.shownTab(tabUnderToast: model.tabUnderToast) else { return nil }
        return registry.tabs.first { $0.id == id }
    }

    private var contentHeight: CGFloat { registry.contentHeight(for: state, tabUnderToast: model.tabUnderToast) }

    private var isOpen: Bool {
        if case .open = state { true } else { false }
    }

    private var allDropTypes: [UTType] {
        registry.tabs.reduce(into: []) { types, tab in types += tab.dropTypes.filter { !types.contains($0) } }
    }

    /// Hands the items to the shown tab when it accepts them, else to the first tab that does.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let types = providers.flatMap(\.registeredTypeIdentifiers)
        let target = shownTab.flatMap { DropRouting.tab(for: types, tabs: [$0]) } ?? DropRouting.tab(for: types, tabs: registry.tabs)
        return registry.tabs.first { $0.id == target }?.onDrop?(providers) ?? false
    }

    var body: some View {
        let size = geometry.shapeSize(for: state, contentHeight: contentHeight)
        let radii = geometry.cornerRadii(for: state)
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        shape
            .fill(NotchTokens.background)
            .overlay(alignment: .top) {
                content
                    .padding(.horizontal, radii.top)
                    .environment(\.notch, NotchHandle(model: model))
            }
            .clipShape(shape)
            .frame(width: size.width, height: size.height)
            .contentShape(shape)
            // Once open, taps belong to the tab content; the root tap only opens the notch.
            .gesture(TapGesture().onEnded { model.click() }, including: isOpen ? .subviews : .all)
            .animation(NotchTokens.spring, value: state)
            .onDrop(of: allDropTypes, isTargeted: Binding(get: { model.isDragging }, set: { if !$0 { model.setDragging(false) } })) { providers in
                drop(providers)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .closed:
            EmptyView()
        case .compact:
            if let entry = activities.current {
                HStack(spacing: 0) {
                    entry.activity.leading.frame(width: geometry.config.compactSideWidth)
                    Spacer(minLength: geometry.notchSize.width)
                    entry.activity.trailing.frame(width: geometry.config.compactSideWidth)
                }
                .frame(height: geometry.notchSize.height)
                .transition(.opacity)
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
                    }
                    if !isOpen {
                        model.toastContent.frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let shownTab {
                shownTab.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Esc while the tab has focus; the panel's cancelOperation covers the rest.
                    .onExitCommand { model.close() }
                    .id(shownTab.id)
            } else {
                Text("Chưa có module nào đang chạy")
                    .foregroundStyle(NotchTokens.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func expanded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchSize.height)
            content()
        }
        .padding([.horizontal, .bottom], NotchTokens.padding)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(NotchTokens.spring.delay(0.08)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        ))
    }
}
