/// Opens Notification Center from the clock while macOS 27's restriction hides apps: the restriction (assessment mode's) blocks
/// it, and the clock's click cannot just be let through after giving the bar back, since the system takes the bar back at some
/// point during that very click and so sometimes opens the panel and sometimes not. So the click is held back entirely (the
/// app's event tap swallows it), the bar given back, one click of MyNotch's own replayed `replayDelay` later, and the
/// restriction put back as soon as the panel shows: the system leaves an open panel open. A panel that never shows gets the
/// restriction back after `openTimeout`.
///
/// A click while the panel is open is the user closing it, which the restriction allows: it is let through. Time comes from the
/// injected scheduler.
public final class MenuBarClockPassage {
    /// Long enough for the system to give the bar back: 300 ms opened the panel every time, 30 ms did not.
    public static let replayDelay: Duration = .milliseconds(300)
    public static let pollInterval: Duration = .milliseconds(25)
    /// From the replay; the panel shows in about 250 ms.
    public static let openTimeout: Duration = .seconds(1)

    /// Whether a click is being passed through now.
    public private(set) var isPassing = false
    /// Each step, for the log.
    public var onStep: ((String) -> Void)?

    private let scheduler: any Scheduler
    private let isPanelOpen: () -> Bool
    private let suspend: () -> Bool
    private let resume: () -> Void
    private let replay: () -> Void
    private var pending: ScheduledAction?

    public init(
        scheduler: any Scheduler, isPanelOpen: @escaping () -> Bool, suspend: @escaping () -> Bool, resume: @escaping () -> Void,
        replay: @escaping () -> Void
    ) {
        self.scheduler = scheduler
        self.isPanelOpen = isPanelOpen
        self.suspend = suspend
        self.resume = resume
        self.replay = replay
    }

    /// A click came down on the clock. True when it is taken over: the caller swallows it and its mouse-up.
    public func clockPressed() -> Bool {
        guard !isPassing else { return false }
        guard !isPanelOpen() else {
            onStep?("clock click let through: Notification Center is open")
            return false
        }
        guard suspend() else { return false }
        isPassing = true
        onStep?("clock click held, menu bar given back")
        pending = scheduler.schedule(after: Self.replayDelay) { [weak self] in
            guard let self else { return }
            onStep?("click replayed")
            replay()
            poll(left: Int(Self.openTimeout / Self.pollInterval))
        }
        return true
    }

    /// Stops a pass under way, leaving the restriction to whoever stops it.
    public func cancel() {
        pending?.cancel()
        pending = nil
        isPassing = false
    }

    private func poll(left: Int) {
        if isPanelOpen() {
            finish("Notification Center open")
        } else if left <= 0 {
            finish("Notification Center did not open")
        } else {
            pending = scheduler.schedule(after: Self.pollInterval) { [weak self] in self?.poll(left: left - 1) }
        }
    }

    private func finish(_ step: String) {
        pending = nil
        isPassing = false
        onStep?("\(step), restriction back")
        resume()
    }
}
