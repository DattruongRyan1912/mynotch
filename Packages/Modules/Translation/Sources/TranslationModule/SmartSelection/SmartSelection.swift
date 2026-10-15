import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// Everything "Bôi đen là hiểu" takes from outside the module; tests replace it with fakes.
struct SmartSelectionSetup {
    var accessibility: any AccessibilityClient = SystemAccessibilityClient()
    var input: any SelectionInputSource = SystemSelectionInput()
    var window: any SelectionChipWindowing = SystemSelectionChipWindow()
    /// Apple's on-device engine, which makes the previews. Not the one the tab translates with: a preview must not
    /// supersede a translation the tab has under way, and no engine that needs a key may ever be put here.
    var preview: any OnDeviceTranslationEngine = AppleTranslationEngine()
    /// The displays, the main one first.
    var screens: () -> [ScreenArea] = { SmartSelectionSetup.systemScreens() }
    var ownProcessID: pid_t = getpid()

    static func systemScreens() -> [ScreenArea] {
        NSScreen.screens.map { ScreenArea(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
}

/// "Bôi đen là hiểu": watches for selections in other apps, understands them (a conversion or a preview of a translation)
/// and shows what it found beside the selection and, if the user wants, beside the collapsed notch.
///
/// Nothing the user selects is written anywhere or sent anywhere from here, and it is held in memory only until the next
/// selection or the end of the module: the preview is on-device, and the selected text is never logged.
///
/// It reads passively, so it must never disturb the app it reads from or the notch: it goes by the front app (no Accessibility
/// call), makes one pass over one element with a short timeout, leaves an app alone for 30 s once it has not answered, and
/// never switches another app into accessibility mode (that is for the shortcut, on the user's press).
final class SmartSelection {
    static let activityID = "selection"
    /// How long an app that did not answer in time is left alone.
    static let coolDown = Duration.seconds(30)

    let decider: SelectionDecider
    /// The newest reading; tests await it. A newer gesture, a click, a key or another app coming forward supersedes it.
    private(set) var reading: Task<Void, Never>?

    private let context: ModuleContext
    private let setup: SmartSelectionSetup
    private let keys: TranslationKeys
    private let openResult: @MainActor (SelectionSource) -> Void
    private var chip: SelectionChip!
    private var watcher: SelectionWatcher?
    private var isWatching = false
    private var watchesKeys = false
    /// The last selection handled, whether it was shown or there was nothing to show: reading the same one again (a drag that
    /// selected nothing new, such as a scrollbar's) is not worth a new chip. A click, a key that is not a selection, another
    /// app coming forward and an empty read make it a new selection again.
    private var lastHandled: SelectionSource?
    /// Bumped by everything that makes a reading in flight stale.
    private var generation = 0
    /// The app a reading in flight is about.
    private var readingProcessID: pid_t?
    /// Apps that did not answer, which are not asked again for `coolDown`.
    private var coolingDown: Set<pid_t> = []

    /// - Parameter open: the chip's "Mở": opens the notch's Translation tab on the selection.
    init(
        context: ModuleContext, setup: SmartSelectionSetup, decider: SelectionDecider, open: @escaping @MainActor (SelectionSource) -> Void
    ) {
        self.context = context
        self.setup = setup
        self.decider = decider
        openResult = open
        keys = TranslationKeys(context.settings)
        chip = SelectionChip(
            scheduler: context.scheduler,
            show: { [weak self] hint, anchor in self?.present(hint, near: anchor) },
            hide: { [weak self] in self?.withdraw() },
            onDismiss: { }
        )
    }

    /// Starts or stops watching to match the settings, and keeps doing so as they change.
    func start() {
        apply()
        context.run { [weak self] in
            for await _ in Observations({ [weak self] in self?.wantsToWatch ?? false }) {
                self?.apply()
            }
        }
    }

    /// Stops watching and takes down what is showing. Nothing runs after this.
    func stop() {
        stopWatching()
        setup.preview.invalidate()
    }

    /// Whether anything would be shown: the feature is on and has a chip or an activity to show it with.
    private var wantsToWatch: Bool {
        let settings = context.settings
        return settings.value(keys.smartSelection) && (settings.value(keys.selectionChip) || settings.value(keys.selectionActivity))
    }

    func apply() {
        switch (wantsToWatch, isWatching) {
        case (true, false): startWatching()
        case (false, true): stopWatching()
        default: break
        }
    }

    // MARK: watching

    private func startWatching() {
        watcher = SelectionWatcher(
            scheduler: context.scheduler,
            onSelection: { [weak self] in self?.selectionGesture(at: $0, byPointer: $1) },
            onDismiss: { [weak self] in self?.selectionMayBeChanging(gone: $0) }
        )
        isWatching = true
        startInput()
    }

    private func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        setup.input.stop()
        watcher?.stop()
        watcher = nil
        supersedeReading()
        chip.dismiss()
        lastHandled = nil
        coolingDown.removeAll()
    }

    /// Key-ups need Accessibility, so they are only asked for once it is granted; the mouse needs nothing, which also lets the
    /// first gesture after the user grants it start listening to keys.
    private func startInput() {
        watchesKeys = setup.accessibility.isTrusted
        setup.input.start({ [weak self] in self?.handle($0) }, keys: watchesKeys)
    }

    private func handle(_ input: SelectionInput) {
        if case .applicationActivated(let processID) = input {
            chip.applicationActivated(processID)
            // The selection being read, and the one handled last, are in an app that is no longer in front.
            if let readingProcessID, readingProcessID != processID { supersedeReading() }
            if let lastHandled, lastHandled.application.processID != processID { self.lastHandled = nil }
            return
        }
        watcher?.handle(input)
    }

    /// A press or a key: whatever was read or shown is about a selection that may be going away. When it is known to be gone,
    /// the same text selected again is a new selection.
    private func selectionMayBeChanging(gone: Bool) {
        supersedeReading()
        chip.dismiss()
        if gone { lastHandled = nil }
    }

    private func supersedeReading() {
        generation += 1
        readingProcessID = nil
        reading?.cancel()
    }

    private func selectionGesture(at pointer: CGPoint, byPointer: Bool) {
        if isWatching, !watchesKeys, setup.accessibility.isTrusted { startInput() }
        supersedeReading()
        let request = generation
        reading = Task { [weak self] in await self?.read(at: pointer, byPointer: byPointer, request: request) }
    }

    // MARK: reading

    private func isCurrent(_ request: Int) -> Bool {
        request == generation && !Task.isCancelled
    }

    private func read(at pointer: CGPoint, byPointer: Bool, request: Int) async {
        let accessibility = setup.accessibility
        let settings = context.settings
        guard accessibility.isTrusted, let application = accessibility.frontmostApplication(),
              SelectionIgnoreRules.application(application, ownProcessID: setup.ownProcessID, denyList: settings.value(keys.selectionDenyList)) == nil,
              !coolingDown.contains(application.processID),
              !accessibility.isSecureInputHeld(by: application) else { return chip.dismiss() }
        readingProcessID = application.processID
        defer { if request == generation { readingProcessID = nil } }
        // One look, which never turns accessibility on in the app: Chrome and Electron apps show their selection here only once
        // the shortcut has switched them on.
        let source: SelectionSource
        let bounds: CGRect?
        switch accessibility.inspectSelection(in: application) {
        case .selected(let text, let found):
            source = SelectionSource(text: text, application: application)
            bounds = found
        case .unresponsive:
            coolDown(application.processID)
            return chip.dismiss()
        case .none, .tooLong:
            lastHandled = nil
            return chip.dismiss()
        }
        if let reason = SelectionIgnoreRules.text(source, lastHandled: lastHandled) {
            if reason != .unchanged {
                lastHandled = nil
                chip.dismiss()
            }
            return
        }
        let hint = await decider.hint(for: source)
        guard isCurrent(request) else { return }
        lastHandled = source
        guard let hint else { return chip.dismiss() }
        let anchor = SelectionGeometry.anchor(bounds: bounds, pointer: pointer, screens: setup.screens(), pointerMatters: byPointer)
        chip.show(hint, anchor: anchor)
    }

    /// The app did not answer in time: it is not asked again for 30 s, so a hung app costs one short wait, not one per drag.
    private func coolDown(_ processID: pid_t) {
        coolingDown.insert(processID)
        context.scheduler.schedule(after: Self.coolDown) { [weak self] in self?.coolingDown.remove(processID) }
    }

    // MARK: showing

    private func present(_ hint: SelectionHint, near anchor: CGRect) {
        let settings = context.settings
        if settings.value(keys.selectionChip) {
            setup.window.show(content(for: hint), near: anchor)
        }
        if settings.value(keys.selectionActivity) {
            context.activities.set(LiveActivity(
                id: Self.activityID, expiresAfter: SelectionChip.lifetime,
                leading: AnyView(SelectionActivityIcon(kind: hint.kind)), trailing: AnyView(SelectionActivityText(text: hint.text)),
                summary: hint.text
            ))
        }
    }

    private func withdraw() {
        setup.window.hide()
        context.activities.clear(id: Self.activityID)
    }

    private func content(for hint: SelectionHint) -> SelectionChipContent {
        let application = hint.source.application
        var deny: (@MainActor () -> Void)?
        if application.bundleID != nil { deny = { [weak self] in self?.deny(application) } }
        return SelectionChipContent(
            kind: hint.kind, text: hint.text,
            open: { [weak self] in self?.openCurrent() },
            deny: deny,
            hover: { [weak self] in self?.chip.hoverChanged($0) }
        )
    }

    /// "Mở": the result of the selection the chip is showing, in the notch.
    private func openCurrent() {
        guard let hint = chip.hint else { return }
        chip.dismiss()
        openResult(hint.source)
    }

    /// "Không hiện trong app này": the app joins the deny list, and nothing more is read from it.
    private func deny(_ application: FocusedApplication) {
        guard let bundleID = application.bundleID else { return }
        let settings = context.settings
        settings.set(SelectionDenyList.adding(bundleID, to: settings.value(keys.selectionDenyList)), for: keys.selectionDenyList)
        supersedeReading()
        chip.dismiss()
    }
}
