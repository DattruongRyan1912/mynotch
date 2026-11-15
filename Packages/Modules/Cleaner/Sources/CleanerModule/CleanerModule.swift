import AppKit
import Foundation
import MyNotchCore
import NotchUI
import SwiftUI
import UniformTypeIdentifiers

/// Phân hệ Gỡ ứng dụng và Dọn dẹp hệ thống trên Notch macOS.
public final class CleanerModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "cleaner",
        displayName: "Gỡ ứng dụng",
        systemImage: "trash",
        defaultEnabled: true,
        order: 970
    )

    public static let dropTypes: [UTType] = [.applicationBundle, .application]

    public let state: CleanerState
    private(set) var context: ModuleContext?

    /// Cache các DeletionPlan được quét cho từng StorageCategory của SystemClean
    var cachedPlans: [String: DeletionPlan] = [:]

    public init(
        state: CleanerState = CleanerState()
    ) {
        self.state = state
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
    }

    public func stop() async {
        self.context = nil
        await MainActor.run {
            self.state.reset()
        }
        self.cachedPlans.removeAll()
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id,
            title: descriptor.displayName,
            systemImage: descriptor.systemImage,
            preferredHeight: CleanerTabView.height,
            acceptsKeyboard: false,
            dropTypes: Self.dropTypes,
            onDrop: { [weak self] providers in
                self?.handleDrop(providers) ?? false
            },
            content: AnyView(CleanerTabView(state: state))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        nil
    }

    @discardableResult
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Priority 1: Direct drag pasteboard read (synchronous, instant, zero latency)
        if let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let appURL = urls.first(where: { DropRouting.isApplicationURL($0) }) {
            Task { @MainActor in
                state.analyze(appURL: appURL.standardized)
            }
            return true
        }

        // Priority 2: Asynchronous item provider fallback
        guard let item = providers.first else { return false }
        _ = item.loadObject(ofClass: URL.self) { [weak self] url, _ in
            guard let rawURL = url else { return }
            let appURL = rawURL.standardized
            guard DropRouting.isApplicationURL(appURL) else { return }
            Task { @MainActor in
                self?.state.analyze(appURL: appURL)
            }
        }
        return true
    }
}
