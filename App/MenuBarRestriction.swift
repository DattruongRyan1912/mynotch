import AppKit
import MyNotchCore

/// macOS 27's restriction of the menu bar to a list of apps, from the private MenuBarClientCore framework that assessment
/// (exam) mode uses: the only way left there to take other apps' items off the menu bar, since a long status item is dropped
/// instead of pushing them away. Everything is looked up at run time and checked before use, so a macOS that changes or drops
/// it makes `isAvailable` false rather than crashing; Swift cannot catch an Objective-C exception, so the checks are all the
/// guard there is. The restriction belongs to the process: if MyNotch quits or crashes, the system gives the bar back.
final class MenuBarRestriction: MenuBarRestrictionProvider {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let initSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")
    /// The system's own items go by number (2 the clock, 5 Sound, 6 Wi-Fi, 8 Control Center); numbers it does not know are
    /// ignored, so all of them up to its limit keep every one shown.
    private static let systemItems = (0...63).map { NSNumber(value: $0) }

    private typealias ActivateFunction = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (NSError?) -> Void) -> Void
    private typealias InvalidateFunction = @convention(c) (AnyObject, Selector) -> Void

    private static let classes: (configuration: NSObject.Type, assertion: NSObject.Type)? = {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
              dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) != nil,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              configuration.instancesRespond(to: initSelector),
              assertion.instancesRespond(to: activateSelector),
              assertion.instancesRespond(to: invalidateSelector) else { return nil }
        return (configuration, assertion)
    }()

    /// Whether this macOS has the restriction and it would keep MyNotch's own items: the allow-list matches an app's items
    /// only for the copy Launch Services resolves its bundle ID to, and a copy run from anywhere else would hide its own icon,
    /// the way back.
    static var isAvailable: Bool {
        guard classes != nil, let id = Bundle.main.bundleIdentifier,
              let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
        return resolved.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// The restriction in force, held until it is replaced or lifted.
    private var current: NSObject?
    /// Bumped by every request, so one that is overtaken while it is being set up is undone when it lands.
    private var generation = 0

    func restrict(toApps allowed: [String], completion: @escaping @MainActor (Bool) -> Void) {
        generation += 1
        let mine = generation
        Log.logger(category: "app").notice(
            "Menu-bar hider: keeping \(allowed.count) apps on the menu bar, MyNotch among them: \(allowed.contains(Bundle.main.bundleIdentifier ?? ""))"
        )
        guard let classes = Self.classes,
              let configuration = Self.makeConfiguration(classes.configuration, allowed: allowed) else {
            completion(false)
            return
        }
        let assertion = classes.assertion.init()
        let activate = unsafeBitCast(assertion.method(for: Self.activateSelector), to: ActivateFunction.self)
        // The new restriction is set before the old one goes, so nothing hidden by both shows in between.
        activate(assertion, Self.activateSelector, configuration) { [weak self] error in
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in self?.landed(assertion, failure: failure, generation: mine, completion: completion) }
        }
    }

    /// A restriction was set up, or refused. One overtaken meanwhile is undone and not reported.
    private func landed(_ assertion: NSObject, failure: String?, generation mine: Int, completion: @MainActor (Bool) -> Void) {
        if let failure {
            Log.logger(category: "app").error("Menu-bar hider: the system refused the restriction: \(failure, privacy: .public)")
            if mine == generation { completion(false) }
            return
        }
        guard mine == generation else {
            Self.invalidate(assertion)
            return
        }
        if let current { Self.invalidate(current) }
        current = assertion
        completion(true)
    }

    func lift() {
        generation += 1
        if let current { Self.invalidate(current) }
        current = nil
    }

    /// `alloc` and an `init…` through `perform`, which hands back exactly what the methods return: `alloc`'s object is left
    /// owned for the `init` that consumes it, and the `init`'s result is owned by the caller.
    private static func makeConfiguration(_ type: NSObject.Type, allowed: [String]) -> AnyObject? {
        guard let allocated = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        // Both lists must be arrays: the framework indexes into them.
        return allocated.perform(initSelector, with: systemItems as NSArray, with: allowed as NSArray)?.takeRetainedValue()
    }

    private static func invalidate(_ assertion: NSObject) {
        let invalidate = unsafeBitCast(assertion.method(for: invalidateSelector), to: InvalidateFunction.self)
        invalidate(assertion, invalidateSelector)
    }
}
