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
    var preview: any TranslationEngine = AppleTranslationEngine()
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
/// Nothing the user selects is kept longer than the chip is up, written anywhere or sent anywhere from here: the preview
/// is on-device, and the selected text is never logged.
final class SmartSelection {
    static let activityID = "selection"

    let decider: SelectionDecider
    /// The newest reading; tests await it. A newer gesture, a click, a key or another app coming forward supersedes it.
    private(set) var reading: Task<Void, Never>?

    private let context: ModuleContext
    private let setup: SmartSelectionSetup
    private let reader: SelectionReader
    private let keys: TranslationKeys
    private let openResult: @MainActor (SelectionSource) -> Void
    private var chip: SelectionChip!
    private var watcher: SelectionWatcher?
    private var isWatching = false
    private var watchesKeys = false
    /// The selection the chip shows now; a read of the same one is not worth a new chip.
    private var lastShown: SelectionSource?
    /// Bumped by everything that makes a reading in flight stale.
    private var generation = 0
    /// The app a reading in flight is about.
    private var readingProcessID: pid_t?

    /// - Parameter open: the chip's "Mở": opens the notch's Translation tab on the selection.
    init(
        context: ModuleContext, setup: SmartSelectionSetup, reader: SelectionReader, decider: SelectionDecider,
        open: @escaping @MainActor (SelectionSource) -> Void
    ) {
        self.context = context
        self.setup = setup
        self.reader = reader
        self.decider = decider
        openResult = open
        keys = TranslationKeys(context.settings)
        chip = SelectionChip(
            scheduler: context.scheduler,
            show: { [weak self] hint, anchor in self?.present(hint, near: anchor) },
            hide: { [weak self] in self?.withdraw() },
            onDismiss: { [weak self] in self?.lastShown = nil }
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
            onSelection: { [weak self] in self?.selectionGesture(at: $0) },
            onDismiss: { [weak self] in self?.selectionMayBeChanging() }
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
            // The selection being read is in an app that is no longer in front.
            if let readingProcessID, readingProcessID != processID { supersedeReading() }
            return
        }
        watcher?.handle(input)
    }

    /// A press or a key: whatever was read or shown is about a selection that may be going away.
    private func selectionMayBeChanging() {
        supersedeReading()
        chip.dismiss()
    }

    private func supersedeReading() {
        generation += 1
        readingProcessID = nil
        reading?.cancel()
    }

    private func selectionGesture(at pointer: CGPoint) {
        if isWatching, !watchesKeys, setup.accessibility.isTrusted { startInput() }
        supersedeReading()
        let request = generation
        reading = Task { [weak self] in await self?.read(at: pointer, request: request) }
    }

    // MARK: reading

    private func isCurrent(_ request: Int) -> Bool {
        request == generation && !Task.isCancelled
    }

    private func read(at pointer: CGPoint, request: Int) async {
        let accessibility = setup.accessibility
        let settings = context.settings
        guard accessibility.isTrusted, let application = accessibility.focusedApplication(),
              SelectionIgnoreRules.application(application, ownProcessID: setup.ownProcessID, denyList: settings.value(keys.selectionDenyList)) == nil,
              SelectionIgnoreRules.length(accessibility.selectionLength(in: application)) == nil else { return chip.dismiss() }
        readingProcessID = application.processID
        defer { if request == generation { readingProcessID = nil } }
        // The same choice the shortcut honours: whether to switch Chrome and Electron apps into the mode that exposes text.
        reader.useChromiumAccessibility = settings.value(keys.useChromiumAccessibility)
        guard let source = await reader.selection(), isCurrent(request) else {
            if isCurrent(request) { chip.dismiss() }
            return
        }
        guard source.application == application else { return chip.dismiss() }
        if let reason = SelectionIgnoreRules.text(source, lastShown: lastShown) {
            if reason != .unchanged { chip.dismiss() }
            return
        }
        let hint = await decider.hint(for: source)
        guard isCurrent(request) else { return }
        guard let hint else { return chip.dismiss() }
        let anchor = SelectionGeometry.anchor(bounds: accessibility.selectionBounds(in: application), pointer: pointer, screens: setup.screens())
        lastShown = source
        chip.show(hint, anchor: anchor)
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
