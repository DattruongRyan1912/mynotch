import AppKit
import MyNotchCore
import Observation
import SwiftUI

// MARK: - AppKit Visual Effect Background

@MainActor
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Apple Sidebar Icon Badge

struct AppleSidebarIconBadge: View {
    let visuals: AppleSettingsVisuals
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [visuals.color.opacity(0.95), visuals.color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
                )
                .shadow(color: visuals.color.opacity(0.25), radius: 1, x: 0, y: 1)

            Image(systemName: visuals.systemImage)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Root View

struct SettingsRootView: View {
    let settings: SettingsStore
    let registry: ModuleRegistry
    let permissions: any PermissionCenter
    let overview: PermissionOverview
    let hotkeys: HotkeyRegistry
    let configSync: ConfigSyncService
    @Bindable var navigation: SettingsNavigation
    @State private var searchText = ""
    @State private var isShowingHelp = false

    private var selectionBinding: Binding<SettingsPage?> {
        Binding(
            get: { navigation.selection },
            set: { if let page = $0 { navigation.select(page) } }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detailContent
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: selectionBinding) {
            if searchText.isEmpty {
                Section {
                    profileRow
                }
                Section {
                    coreRows
                }
                Section("MÔ-ĐUN") {
                    moduleRows
                }
            } else {
                filteredSection
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Tìm kiếm")
    }

    private var profileRow: some View {
        let userName = NSFullUserName()
        return Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(userName.isEmpty ? "MyNotch" : userName)
                    .font(.system(size: 13, weight: .semibold))
                Text("Cài đặt MyNotch")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } icon: {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 14))
                    )
            }
        }
        .tag(SettingsPage.about)
    }

    @ViewBuilder
    private var coreRows: some View {
        Label {
            Text("Quyền")
        } icon: {
            AppleSidebarIconBadge(visuals: .forPage(.permissions), size: 20)
        }
        .badge(overview.missingRequiredCount)
        .tag(SettingsPage.permissions)

        Label {
            Text("Chung")
        } icon: {
            AppleSidebarIconBadge(visuals: .forPage(.general), size: 20)
        }
        .tag(SettingsPage.general)

        Label {
            Text("Giao diện")
        } icon: {
            AppleSidebarIconBadge(visuals: .forPage(.interface), size: 20)
        }
        .tag(SettingsPage.interface)

        Label {
            Text("Dung lượng")
        } icon: {
            AppleSidebarIconBadge(visuals: .forPage(.storage), size: 20)
        }
        .tag(SettingsPage.storage)

        Label {
            Text("Trang trên notch")
        } icon: {
            AppleSidebarIconBadge(visuals: .forPage(.tabs), size: 20)
        }
        .tag(SettingsPage.tabs)
    }

    @ViewBuilder
    private var moduleRows: some View {
        ForEach(registry.modules, id: \.descriptor.id) { module in
            Label {
                Text(module.descriptor.displayName)
            } icon: {
                AppleSidebarIconBadge(
                    visuals: AppleSettingsVisuals.forModule(
                        module.descriptor.id,
                        fallbackImage: module.descriptor.systemImage
                    ),
                    size: 20
                )
            }
            .tag(SettingsPage.module(module.descriptor.id))
        }
    }

    @ViewBuilder
    private var filteredSection: some View {
        let query = searchText.lowercased()
        let matchingCore: [(String, SettingsPage)] = [
            ("Quyền", .permissions),
            ("Chung", .general),
            ("Giao diện", .interface),
            ("Dung lượng", .storage),
            ("Trang trên notch", .tabs),
            ("Giới thiệu", .about)
        ].filter { $0.0.lowercased().contains(query) }

        let matchingModules = registry.modules.filter {
            $0.descriptor.displayName.lowercased().contains(query) ||
            $0.descriptor.id.rawValue.lowercased().contains(query)
        }

        if matchingCore.isEmpty && matchingModules.isEmpty {
            Text("Không tìm thấy kết quả")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 16)
        } else {
            ForEach(matchingCore, id: \.1) { name, page in
                Label {
                    Text(name)
                } icon: {
                    AppleSidebarIconBadge(visuals: .forPage(page), size: 20)
                }
                .tag(page)
            }
            ForEach(matchingModules, id: \.descriptor.id) { module in
                Label {
                    Text(module.descriptor.displayName)
                } icon: {
                    AppleSidebarIconBadge(
                        visuals: AppleSettingsVisuals.forModule(
                            module.descriptor.id,
                            fallbackImage: module.descriptor.systemImage
                        ),
                        size: 20
                    )
                }
                .tag(SettingsPage.module(module.descriptor.id))
            }
        }
    }

    // MARK: - Detail Pane

    private var detailContent: some View {
        detailBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(currentPageTitle)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        navigation.goBack()
                    } label: {
                        Label("Quay lại", systemImage: "chevron.left")
                    }
                    .disabled(!navigation.canGoBack)
                    .help("Quay lại (⌘[)")

                    Button {
                        navigation.goForward()
                    } label: {
                        Label("Tiến tới", systemImage: "chevron.right")
                    }
                    .disabled(!navigation.canGoForward)
                    .help("Tiến tới (⌘])")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingHelp.toggle()
                    } label: {
                        Label("Trợ giúp", systemImage: "questionmark.circle")
                    }
                    .help("Trợ giúp")
                    .popover(isPresented: $isShowingHelp, arrowEdge: .bottom) {
                        helpPopoverContent
                    }
                }
            }
            .background {
                Group {
                    Button("Quay lại") { navigation.goBack() }
                        .keyboardShortcut("[", modifiers: .command)
                        .disabled(!navigation.canGoBack)
                    Button("Tiến tới") { navigation.goForward() }
                        .keyboardShortcut("]", modifiers: .command)
                        .disabled(!navigation.canGoForward)
                }
                .opacity(0)
                .accessibilityHidden(true)
            }
    }

    private var helpPopoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trợ giúp")
                .font(.system(size: 12, weight: .bold))
            Text(helpText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 240)
        }
        .padding(10)
    }

    private var currentPageTitle: String {
        switch navigation.selection ?? .general {
        case .permissions: return "Quyền"
        case .general: return "Chung"
        case .interface: return "Giao diện"
        case .storage: return "Dung lượng"
        case .tabs: return "Trang trên notch"
        case .about: return "Giới thiệu"
        case .module(let id):
            return registry.modules.first { $0.descriptor.id == id }?.descriptor.displayName ?? id.rawValue
        }
    }

    @ViewBuilder
    private var detailBody: some View {
        switch navigation.selection ?? .general {
        case .permissions:
            PermissionsPage(overview: overview)
        case .general:
            GeneralSettingsPage(settings: settings, hotkeys: hotkeys, configSync: configSync)
        case .interface:
            InterfaceSettingsPage(settings: settings)
        case .storage:
            StoragePage(settings: settings, registry: registry, openModule: { navigation.select(.module($0)) })
        case .tabs:
            TabOrderSettingsPage(settings: settings, registry: registry)
        case .module(let id):
            ModuleSettingsPage(id: id, registry: registry, permissions: permissions).id(id)
        case .about:
            AboutPage()
        }
    }

    private var helpText: String {
        switch navigation.selection ?? .general {
        case .permissions:
            return "Kiểm tra và cấp các quyền hệ thống macOS (TCC) cần thiết để các mô-đun MyNotch hoạt động đầy đủ."
        case .general:
            return "Cấu hình khởi động cùng máy, ẩn hiện biểu tượng menu bar, phím tắt toàn cục và quản lý file cấu hình dotfiles."
        case .interface:
            return "Tuỳ chỉnh hiển thị thanh notch, kích thước, hiệu ứng mở rộng, hoạt ảnh và độ mờ."
        case .storage:
            return "Quản lý dữ liệu lưu trữ cục bộ, bộ nhớ đệm và các tệp nhật ký của từng mô-đun."
        case .tabs:
            return "Sắp xếp thứ tự các thẻ trên thanh notch hoặc đưa các mô-đun ít dùng vào danh mục 'Khác'."
        case .about:
            return "Thông tin phiên bản, bản quyền và các thư viện mã nguồn mở MyNotch sử dụng."
        case .module:
            return "Bật/tắt mô-đun này, kiểm tra trạng thái hoạt động và tuỳ chỉnh các tính năng chuyên sâu."
        }
    }
}
