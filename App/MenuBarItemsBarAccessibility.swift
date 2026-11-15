import AppKit
import ApplicationServices
import MyNotchCore

/// The apps' status items through the Accessibility API: every running app's `AXExtrasMenuBar` and its children. Of each item only
/// the title, the description and the frame are read, and none of them is logged. Reading never prompts: without the permission
/// every call simply fails, and `isTrusted` says so first.
final class AccessibilityMenuBarItemSource: MenuBarItemSource {
    /// A hung app would hold each call until the timeout, and the main thread with it (a press and a frame are asked from there).
    private nonisolated static let readTimeout: Float = 0.15
    /// A press may not return until the app's menu is closed; the call gives up after this and counts as taken.
    private static let pressTimeout: Float = 0.3

    /// The elements of the last list, by item ID. Only the main actor touches it.
    private var elements: [String: ElementBox] = [:]

    var isTrusted: Bool { AXIsProcessTrusted() }

    func items() async -> [MenuBarItem] {
        guard isTrusted else {
            elements = [:]
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidates = NSWorkspace.shared.runningApplications.compactMap { app -> Candidate? in
            guard !app.isTerminated, app.activationPolicy != .prohibited,
                  MenuBarItemOwners.isListed(bundleID: app.bundleIdentifier, pid: app.processIdentifier, ownPID: ownPID) else { return nil }
            return Candidate(pid: app.processIdentifier, bundleID: app.bundleIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "App")
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let read = await Self.read(candidates, primaryHeight: primaryHeight)
        elements = Dictionary(uniqueKeysWithValues: read.map { ($0.item.id, $0.box) })
        return read.map(\.item)
    }

    func currentFrame(of id: String) -> CGRect? {
        guard let element = elements[id]?.element else { return nil }
        AXUIElementSetMessagingTimeout(element, Self.readTimeout)
        guard let frame = Self.frame(of: element) else { return nil }
        return MenuBarCoordinates.appKitFrame(fromAccessibility: frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    func perform(_ action: MenuBarItemAction, on id: String) -> MenuBarItemActionResult {
        guard let element = elements[id]?.element else { return .failed }
        AXUIElementSetMessagingTimeout(element, Self.pressTimeout)
        let name = action == .press ? kAXPressAction : kAXShowMenuAction
        switch AXUIElementPerformAction(element, name as CFString) {
        case .success, .cannotComplete:
            // A timeout is what an app answers with while its menu is open and tracking.
            return .performed
        case .actionUnsupported:
            return .unsupported
        default:
            return .failed
        }
    }

    // MARK: reading

    private nonisolated struct Candidate: Sendable {
        let pid: Int32
        let bundleID: String?
        let name: String
    }

    /// An `AXUIElement` is a thread-safe handle to the other app's element; Swift cannot know it.
    private nonisolated struct ElementBox: @unchecked Sendable {
        let element: AXUIElement
    }

    private nonisolated struct ReadItem: Sendable {
        let item: MenuBarItem
        let box: ElementBox
    }

    /// Every app is asked at the same time, off the main thread, each with a short timeout of its own. The order of the result is the
    /// order of `candidates`, and within an app the order of its items.
    private nonisolated static func read(_ candidates: [Candidate], primaryHeight: CGFloat) async -> [ReadItem] {
        await withTaskGroup(of: (Int, [ReadItem]).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { (index, readItems(of: candidate, order: index, primaryHeight: primaryHeight)) }
            }
            var found: [(Int, [ReadItem])] = []
            for await result in group where !result.1.isEmpty { found.append(result) }
            return found.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    private nonisolated static func readItems(of candidate: Candidate, order: Int, primaryHeight: CGFloat) -> [ReadItem] {
        let application = AXUIElementCreateApplication(candidate.pid)
        AXUIElementSetMessagingTimeout(application, readTimeout)
        guard let bar = element(application, kAXExtrasMenuBarAttribute),
              let children = copy(bar, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return children.enumerated().map { position, child in
            AXUIElementSetMessagingTimeout(child, readTimeout)
            let frame = frame(of: child).map { MenuBarCoordinates.appKitFrame(fromAccessibility: $0, primaryHeight: primaryHeight) } ?? .zero
            let item = MenuBarItem(
                id: "\(candidate.pid):\(position)", pid: candidate.pid, ownerBundleID: candidate.bundleID, ownerName: candidate.name,
                title: copy(child, kAXTitleAttribute) as? String, details: copy(child, kAXDescriptionAttribute) as? String,
                frame: frame, order: order * 1_000 + position
            )
            return ReadItem(item: item, box: ElementBox(element: child))
        }
    }

    private nonisolated static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success ? raw : nil
    }

    private nonisolated static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }

    /// The element's frame in Accessibility's coordinates (origin top left of the primary display), nil without position or size.
    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = value(element, kAXPositionAttribute, as: .cgPoint), AXValueGetValue(position, .cgPoint, &origin),
              let extent = value(element, kAXSizeAttribute, as: .cgSize), AXValueGetValue(extent, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private nonisolated static func value(_ element: AXUIElement, _ attribute: String, as type: AXValueType) -> AXValue? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(raw, to: AXValue.self)
        return AXValueGetType(value) == type ? value : nil
    }
}
