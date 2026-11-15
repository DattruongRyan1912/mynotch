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
    /// A preview that is cancelled (a newer selection) never holds up the next one: after a short grace the next goes to a
    /// session of its own, whether or not the framework stops the old translation.
    var preview: any OnDeviceTranslationEngine = SmartSelectionSetup.systemPreview()
    /// The displays, the main one first.
    var screens: () -> [ScreenArea] = { SmartSelectionSetup.systemScreens() }
    /// Where the pointer is, which the small translate button asks while it is up: it goes when the pointer leaves for far away.
    var pointer: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    var ownProcessID: pid_t = getpid()
    /// Where it tells what it is doing: the unified log, category `smart-selection`.
    var log: any SelectionLog = OSSelectionLog()
    /// What was already said once in this run of the app (the module may start more than once).
    var notices = SelectionNotices()
    /// The wait between two looks at an app that has just been switched into accessibility mode.
    var pause: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// Puts a notice up in the notch; nil goes through the module's presenter. Tests record what was asked for.
    var showToast: (@MainActor (AnyView, Duration) -> Void)?
    /// An app's name for the notice that says it was hidden.
    var applicationName: (FocusedApplication) -> String = { SmartSelectionSetup.systemName(of: $0) }

    static func systemName(of application: FocusedApplication) -> String {
        NSRunningApplication(processIdentifier: application.processID)?.localizedName
            ?? application.bundleID.map(RunningApplications.system.name) ?? "app này"
    }

    /// How long a cancelled preview may run on before the next one goes to a session of its own.
    static let previewGrace = Duration.milliseconds(150)

    static func systemPreview() -> AppleTranslationEngine {
        AppleTranslationEngine(graceForCancelled: previewGrace)
    }

    static func systemScreens() -> [ScreenArea] {
        NSScreen.screens.map { ScreenArea(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
}

/// "Bôi đen là hiểu": watches for selections in other apps, understands them (a conversion or a preview of a translation)
/// and shows what it found beside the selection and, if the user wants, beside the collapsed notch. A selection that is read
/// but not translated by itself, for a reason that is only a guess (a name or heading, one word, a doubtful language, the
/// user's own language), gets a small translate button instead, which opens it in the tab, translated.
///
/// Nothing the user selects is written anywhere or sent anywhere from here, and it is held in memory only until the next
/// selection or the end of the module: the preview is on-device, and the selected text is never logged.
///
/// It reads passively, so it must not disturb the app it reads from or the notch: it goes by the front app (no Accessibility
/// call), makes one pass over one element with a short timeout, and leaves an app alone for 30 s once it has not answered. The
/// one thing it does to another app is what the shortcut does too, and only when the user allows it ("Đọc vùng chọn trong
/// Chrome và app Electron", on by default): once per process, it switches a Chrome or Electron app that shows no selection
/// into accessibility mode, which those apps need to say what is selected.
///
/// Every reading says in the log what it ended with, as a code (see `SelectionLog`), so that a selection that shows nothing can
/// be explained.
final class SmartSelection {
    static let activityID = "selection"
    /// How long an app that did not answer in time is left alone.
    static let coolDown = Duration.seconds(30)
    /// A Chrome or Electron app that was just switched into accessibility mode builds its tree on its own time: it is looked at
    /// again every tenth of a second, up to this many times.
    static let treeLooks = 6
    static let treeInterval = Duration.milliseconds(100)
    /// How long the notice about the missing permission stays up.
    static let noticeDuration = Duration.seconds(10)
    /// How long the notice about a hidden app asks to stay. The undo lasts as long as the notice is really up, which can be longer.
    static let undoDuration = Duration.seconds(5)

    /// What "Hoàn tác" undoes: the app that was put on the deny list, and whether this is what put it there. `id` tells one
    /// hiding from the next, so the end of an older notice does not end the newer one's undo.
    struct Denial {
        var id: Int
        var bundleID: String
        var appName: String
        var added: Bool
    }

    /// The hiding that can still be undone: for as long as the notice that has its button is on screen, which can be longer than
    /// the notice asked for, since the notch keeps one up while the pointer is in it. Tests read it.
    private(set) var pendingUndo: Denial?

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
    /// Processes already switched into accessibility mode, or found in it: once is enough for as long as the process lives.
    private var switchedOn: Set<pid_t> = []
    private var denialCount = 0
    /// A key that does not change a selection was pressed since the selection was made (⌘C, typing): the user has what they
    /// wanted from it, so the small translate button is not offered. The watcher lets ⌘C be, so this is the button's own note.
    private var keyPressedSinceSelection = false

    /// - Parameters:
    /// - Parameter open: the chip's "Mở" and the small button's click: opens the notch's Translation tab on the selection,
    ///   translated at once.
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
            onDismiss: { },
            pointer: setup.pointer
        )
    }

    /// Starts or stops watching to match the settings, and keeps doing so as they change.
    func start() {
        apply()
        log(.start(watcher: isWatching, trusted: setup.accessibility.isTrusted, keys: watchesKeys))
        context.run { [weak self] in
            for await _ in Observations({ [weak self] in self?.wantsToWatch ?? false }) {
                self?.apply(logging: true)
            }
        }
    }

    /// Stops watching and takes down what is showing. Nothing runs after this.
    func stop() {
        stopWatching()
        setup.preview.invalidate()
    }

    /// Whether anything would be shown: the feature is on and has a chip, an activity or the small button to show it with.
    private var wantsToWatch: Bool {
        let settings = context.settings
        return settings.value(keys.smartSelection)
            && (settings.value(keys.selectionChip) || settings.value(keys.selectionActivity) || settings.value(keys.selectionButton))
    }

    func apply(logging: Bool = false) {
        switch (wantsToWatch, isWatching) {
        case (true, false):
            startWatching()
            if logging { log(.watcher(on: true, keys: watchesKeys)) }
        case (false, true):
            stopWatching()
            if logging { log(.watcher(on: false, keys: false)) }
        default: break
        }
    }

    private func log(_ line: SelectionLogLine) {
        setup.log.write(line)
    }

    private func skip(_ reason: SelectionSkip) {
        log(.skip(reason))
        // The same selection is still what the chip shows; any other reason means it is no longer the one worth showing.
        if reason != .unchanged { chip.dismiss() }
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
        switchedOn.removeAll()
        pendingUndo = nil
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
        // Any key puts the small translate button away, or keeps it from coming up if the selection is still being read. The watcher
        // lets ⌘C be, since a chip's result is still worth seeing after a copy; the button only offers a translation, which
        // someone who has copied the text does not need, and it must not flash after a quick drag and copy.
        switch input {
        case .keyUp(let key, _):
            keyPressedSinceSelection = !key.changesSelection
            if chip.hint?.kind == .translateButton { chip.dismiss() }
        case .mouseDown, .mouseUp:
            keyPressedSinceSelection = false
        case .applicationActivated:
            break
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
        log(.gesture(pointer: byPointer, keys: watchesKeys))
        if isWatching, !watchesKeys, setup.accessibility.isTrusted {
            startInput()
            log("keys on trusted=1")
        }
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
        guard accessibility.isTrusted else {
            skip(.notTrusted)
            return announceMissingAccessibility()
        }
        guard let application = accessibility.frontmostApplication() else { return skip(.noFrontApp) }
        if let reason = SelectionIgnoreRules.application(application, ownProcessID: setup.ownProcessID, denyList: settings.value(keys.selectionDenyList)) {
            return skip(reason == .ownApplication ? .ownApp : .denied)
        }
        guard !coolingDown.contains(application.processID) else { return skip(.cooldown) }
        guard !accessibility.isSecureInputHeld(by: application) else { return skip(.secure) }
        readingProcessID = application.processID
        defer { if request == generation { readingProcessID = nil } }
        // One look. A Chrome or Electron app that shows nothing may only be hiding it: with the user's leave it is switched into
        // accessibility mode, once per process, and looked at again while it builds its tree. While it does, a look that does not
        // answer in time is as good as one that finds nothing: Chromium is busy building, not hung.
        var inspection = accessibility.inspectSelection(in: application)
        var wasWakingUp = false
        if case .none = inspection, switchOnAccessibility(of: application) {
            wasWakingUp = true
            for _ in 0..<Self.treeLooks {
                do {
                    try await setup.pause(Self.treeInterval)
                } catch {
                    return
                }
                guard isCurrent(request) else { return }
                inspection = accessibility.inspectSelection(in: application)
                switch inspection {
                case .none, .unresponsive: continue
                case .selected, .tooLong: break
                }
                break
            }
        }
        let source: SelectionSource
        let bounds: CGRect?
        switch inspection {
        case .selected(let text, let found):
            source = SelectionSource(text: text, application: application)
            bounds = found
        case .unresponsive where wasWakingUp:
            // Still not answering after the looks that follow the switch-on: nothing to show yet, and no cool-down, which would
            // silence the app for 30 s at the very moment it starts to be readable.
            lastHandled = nil
            return skip(.none)
        case .unresponsive:
            coolDown(application.processID)
            return skip(.unresponsive)
        case .none:
            lastHandled = nil
            return skip(.none)
        case .tooLong:
            lastHandled = nil
            return skip(.tooLong)
        }
        if let reason = SelectionIgnoreRules.text(source, lastHandled: lastHandled) {
            if reason != .unchanged { lastHandled = nil }
            return skip(reason == .empty ? .blank : reason == .tooLong ? .tooLong : .unchanged)
        }
        let decision = await decider.decide(for: source)
        guard isCurrent(request) else { return }
        lastHandled = source
        let anchor = SelectionGeometry.anchor(bounds: bounds, pointer: pointer, screens: setup.screens(), pointerMatters: byPointer)
        switch decision {
        case .skip(let reason):
            skip(reason)
            if reason.offersButton { offerButton(for: source, because: reason, anchor: anchor, pointer: pointer, byPointer: byPointer) }
        case .hint(let hint, let failure):
            if let failure { log(.previewFailed(failure)) }
            log(.hint(hint.kind))
            chip.show(hint, anchor: anchor)
        }
    }

    /// The selection was read and skipped for a reason that is only a guess: a small translate button at the end of it, if the
    /// user wants one. It is shown after a short delay, and the log says so only when it is.
    private func offerButton(for source: SelectionSource, because reason: SelectionSkip, anchor: CGRect, pointer: CGPoint, byPointer: Bool) {
        guard context.settings.value(keys.selectionButton), !keyPressedSinceSelection else { return }
        let end = SelectionGeometry.endAnchor(of: anchor, pointer: pointer, byPointer: byPointer)
        chip.show(SelectionHint(kind: .translateButton, text: "", source: source, reason: reason), anchor: end, watchesPointer: byPointer)
    }

    /// Switches a Chrome or Electron app into accessibility mode, the way the shortcut does, when the user allows it and it is
    /// not done yet for this process. True when it was done now, so the app needs a moment to build what it shows.
    private func switchOnAccessibility(of application: FocusedApplication) -> Bool {
        guard context.settings.value(keys.useChromiumAccessibility),
              let attribute = application.bundleID.flatMap({ SelectionReader.accessibilityAttributes[$0] }),
              switchedOn.insert(application.processID).inserted else { return false }
        guard !setup.accessibility.isEnabled(attribute, in: application) else { return false }
        guard setup.accessibility.enable(attribute, in: application) else {
            // The app refused it: there is no tree to wait for.
            log(.accessibilityRefused(attribute))
            return false
        }
        log(.accessibilityEnabled(attribute))
        return true
    }

    // MARK: the permission

    /// Without Accessibility nothing can be read, and it used to show nothing, which looks like a broken feature: the first
    /// selection of the run says what is missing, with the button that asks for it.
    private func announceMissingAccessibility() {
        guard setup.notices.claim() else { return }
        log("notice accessibility")
        showToast(AnyView(SelectionAccessibilityNotice { [weak self] in self?.requestAccessibility() }), for: Self.noticeDuration)
    }

    private func showToast(_ content: AnyView, for duration: Duration) {
        if let showToast = setup.showToast {
            showToast(content, duration)
        } else {
            context.presenter.showToast(content, duration: duration)
        }
    }

    /// The notice's button: the system's prompt (which lists MyNotch in the Accessibility pane), then that pane when the prompt
    /// alone did not allow it, as the Translation tab does.
    @discardableResult
    func requestAccessibility() -> Task<Void, Never> {
        let permissions = context.permissions
        return Task {
            if await permissions.request(.accessibility) != .granted {
                permissions.openSystemSettings(for: .accessibility)
            }
        }
    }

    /// The app did not answer in time: it is not asked again for 30 s, so a hung app costs one short wait, not one per drag.
    private func coolDown(_ processID: pid_t) {
        coolingDown.insert(processID)
        context.scheduler.schedule(after: Self.coolDown) { [weak self] in self?.coolingDown.remove(processID) }
    }

    // MARK: showing

    private func present(_ hint: SelectionHint, near anchor: CGRect) {
        let settings = context.settings
        if hint.kind == .translateButton {
            // Its own setting and its own look, and never a live activity: "Dịch" beside the notch for every name would be noise.
            guard settings.value(keys.selectionButton), let reason = hint.reason else { return }
            setup.window.show(content(for: hint), near: anchor)
            log(.buttonShown(reason: reason))
            return
        }
        if settings.value(keys.selectionChip) {
            setup.window.show(content(for: hint), near: anchor)
            log("chip shown")
        }
        if settings.value(keys.selectionActivity) {
            // Beside the notch there is room for a line: the first line of a translation, or what a button says.
            let text = hint.kind == .translation ? SelectionHint.firstLine(of: hint.text) ?? hint.text
                : hint.text.isEmpty ? SelectionHint.buttonTitle : hint.text
            context.activities.set(LiveActivity(
                id: Self.activityID, expiresAfter: SelectionChip.lifetime,
                leading: AnyView(SelectionActivityIcon(kind: hint.kind)), trailing: AnyView(SelectionActivityText(text: text)),
                summary: text
            ))
            log("activity shown")
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
        let open: @MainActor () -> Void
        if hint.kind == .translateButton {
            open = { [weak self] in self?.translateButtonClicked() }
        } else {
            open = { [weak self] in self?.openCurrent() }
        }
        return SelectionChipContent(
            kind: hint.kind, text: hint.text, actionTitle: hint.kind == .button ? SelectionHint.buttonTitle : "Mở",
            caption: hint.kind == .translation ? SelectionHint.caption(of: hint.source.text) : nil, note: hint.note,
            open: open,
            deny: deny,
            hover: { [weak self] in self?.chip.hoverChanged($0) }
        )
    }

    /// The small button's click: the tab opens on the selection the button was offered for, translated at once. It is not
    /// read again: by the time of the click a Chrome or Electron app has moved its focus off the text (to the group around
    /// it, which has no selected text), so a second read finds nothing. The button goes first, and a button that is already
    /// gone does nothing.
    private func translateButtonClicked() {
        guard let hint = chip.hint, hint.kind == .translateButton else { return }
        log("button clicked")
        chip.dismiss()
        openResult(hint.source)
    }

    /// "Mở": the result of the selection the chip is showing, in the notch.
    private func openCurrent() {
        guard let hint = chip.hint else { return }
        chip.dismiss()
        openResult(hint.source)
    }

    /// "Không hiện trong app này": the app joins the deny list, and nothing more is read from it. It is not final: the notch says
    /// what was done and for a few seconds offers "Hoàn tác".
    func deny(_ application: FocusedApplication) {
        guard let bundleID = application.bundleID else { return }
        let settings = context.settings
        let before = settings.value(keys.selectionDenyList)
        settings.set(SelectionDenyList.adding(bundleID, to: before), for: keys.selectionDenyList)
        supersedeReading()
        chip.dismiss()
        denialCount += 1
        let denial = Denial(id: denialCount, bundleID: bundleID, appName: setup.applicationName(application), added: !before.contains(bundleID))
        pendingUndo = denial
        log(.deny(added: denial.added))
        showToast(
            AnyView(SelectionDenialNotice(appName: denial.appName, undo: { [weak self] in self?.undoDenial() }, gone: { [weak self] in
                self?.denialNoticeGone(denial.id)
            })),
            for: Self.undoDuration
        )
    }

    /// The notice of the hiding `id` left the screen: its button is gone, so is the way to undo it. A newer hiding has its own.
    func denialNoticeGone(_ id: Int) {
        if pendingUndo?.id == id { pendingUndo = nil }
    }

    /// "Hoàn tác": the app comes off the deny list again, if hiding it is what put it there, and the notice goes.
    func undoDenial() {
        guard let denial = pendingUndo else { return }
        pendingUndo = nil
        // The same text selected again is a new selection now that the app is read again.
        lastHandled = nil
        let settings = context.settings
        if denial.added {
            settings.set(SelectionDenyList.removing(denial.bundleID, from: settings.value(keys.selectionDenyList)), for: keys.selectionDenyList)
        }
        log("deny undone=1")
        context.presenter.close()
    }
}
