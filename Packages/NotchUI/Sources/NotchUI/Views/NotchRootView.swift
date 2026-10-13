import MyNotchCore
import SwiftUI

/// Root SwiftUI view hosted in each notch panel.
struct NotchRootView: View {
    let model: NotchViewModel
    let activities: ActivityCenter
    let registry: ModuleRegistry
    let geometry: NotchGeometry

    private var state: NotchState { model.displayState }

    private var selectedTab: NotchTab? {
        guard case .open(let id) = state, let id else { return nil }
        return registry.tabs.first { $0.id == id }
    }

    private var contentHeight: CGFloat { selectedTab?.contentHeight ?? NotchTab.defaultHeight }

    var body: some View {
        let size = geometry.shapeSize(for: state, contentHeight: contentHeight)
        let radii = geometry.cornerRadii(for: state)
        ZStack(alignment: .top) {
            NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                .fill(NotchTokens.background)
            content
                .padding(.horizontal, radii.top)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        .onTapGesture { model.click() }
        .animation(NotchTokens.spring, value: state)
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
        case .open:
            expanded {
                if registry.tabs.count >= 2 {
                    TabBar(tabs: registry.tabs, selected: selectedTab?.id) { model.open(tab: $0) }
                        .padding(.bottom, 6)
                }
                if let selectedTab {
                    selectedTab.content.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Chưa có module nào đang chạy")
                        .foregroundStyle(NotchTokens.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case .toast:
            expanded { model.toastContent }
        }
    }

    private func expanded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchSize.height)
            content()
        }
        .padding([.horizontal, .bottom], NotchTokens.padding)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(NotchTokens.spring.delay(0.08)))
    }
}
