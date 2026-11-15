import CoreGraphics

/// One separator's status item, as the fitting sees it. The app's adapter wraps the real `NSStatusItem`.
public protocol MenuBarLengthProbe: AnyObject {
    var length: CGFloat { get set }
    /// The item's right edge, the one facing the MyNotch icon, in screen points; nil without a window.
    var trailingEdge: CGFloat? { get }
    /// How far the item could grow leftward on its display at most: from its right edge to the display's left side.
    var room: CGFloat? { get }
}

/// The long length of a separator on macOS 27 and later. There the system draws the whole menu bar itself and drops a status
/// item too long to fit from the layout instead of laying it out, and a dropped item pushes nothing: a 10 000 point separator
/// hides nothing at all. What still fits cannot be computed (it moves with the display, the apps' menus and how full the bar
/// is), so it is measured on the live bar: the separator grows leftward, so while it is laid out its right edge stays where it
/// was, and a dropped one is placed by itself and that edge jumps right. The icons it pushes past the left end of the bar
/// leave it, which is the hiding.
///
/// The measurement is a binary search, one probe per `settleDelay`, about a second in all. It is kept until the displays
/// change (`forget()`), and done again when a check after a layout change finds the separator dropped, at most once per
/// `remeasureCooldown`. Time comes from the injected scheduler.
public final class MenuBarFittedLength {
    /// The system lays the bar out after a length is written; a frame read sooner is the old one.
    public static let settleDelay: Duration = .milliseconds(150)
    /// How far right the edge may move while the item is still laid out.
    public static let ejectionTolerance: CGFloat = 8
    /// The search stops once the bounds are this close.
    public static let precision: CGFloat = 8
    /// Kept below what was measured, so a probe that just fitted is not taken as the limit. Small: any more and the icons
    /// nearest the separator stay shown (an icon is 25–45 points), while one another app adds later and that drops the
    /// separator is caught by the check after the layout change and measured again.
    public static let margin: CGFloat = 12
    /// Shorter than this is no use for hiding: the separator is not long enough to push an icon.
    public static let minimumLength: CGFloat = 40
    /// A dropped separator found by a check is measured again at most this often, so a bar that cannot fit it does not flicker.
    public static let remeasureCooldown: Duration = .seconds(5)

    /// Whether a measurement is under way: the separator's window moves with each probe, which says nothing about the layout.
    public private(set) var isMeasuring = false
    /// The length found, kept until the displays change; nil before the first measurement or when nothing fits.
    public private(set) var fitted: CGFloat?
    /// Called when a measurement ends, whatever it found: the separator's place settled, and what it hides changed.
    public var onMeasured: (() -> Void)?

    private let probe: any MenuBarLengthProbe
    private let scheduler: any Scheduler
    private let normalLength: CGFloat
    private var wantsLong = false
    /// The right edge at the normal length, which a dropped separator's edge departs from.
    private var baseline: CGFloat?
    /// Bumped by anything that makes a probe or a check in flight meaningless.
    private var generation = 0
    private var pending: ScheduledAction?
    private var isChecking = false
    private var cooldown: ScheduledAction?

    public init(probe: any MenuBarLengthProbe, scheduler: any Scheduler, normalLength: CGFloat) {
        self.probe = probe
        self.scheduler = scheduler
        self.normalLength = normalLength
    }

    /// Makes the separator long (the length that fits, measured first if need be) or normal.
    public func apply(long: Bool) {
        wantsLong = long
        guard long else {
            stop()
            probe.length = normalLength
            return
        }
        guard !isMeasuring else { return }
        if let fitted {
            // Writing the length lays the bar out again, so the check reads where the system put it now.
            probe.length = fitted
            scheduleCheck()
        } else {
            measure()
        }
    }

    /// A window moved or the displays woke, so the bar was laid out again: while long, looks whether the separator still fits.
    public func layoutChanged() {
        guard wantsLong, !isMeasuring, fitted != nil else { return }
        scheduleCheck()
    }

    /// The displays changed: what was measured no longer holds. A long separator is measured again now.
    public func forget() {
        fitted = nil
        baseline = nil
        stop()
        if wantsLong { measure() }
    }

    // MARK: measuring

    private func measure() {
        stop()
        isMeasuring = true
        let generation = generation
        probe.length = normalLength
        pending = scheduler.schedule(after: Self.settleDelay) { [weak self] in
            guard let self, generation == self.generation else { return }
            guard let baseline = probe.trailingEdge, let room = probe.room, room > Self.minimumLength else {
                finish(with: nil)
                return
            }
            self.baseline = baseline
            search(low: Self.minimumLength, high: room, best: nil, generation: generation)
        }
    }

    private func search(low: CGFloat, high: CGFloat, best: CGFloat?, generation: Int) {
        guard high - low > Self.precision else {
            finish(with: best.map { $0 - Self.margin })
            return
        }
        let mid = ((low + high) / 2).rounded()
        probe.length = mid
        pending = scheduler.schedule(after: Self.settleDelay) { [weak self] in
            guard let self, generation == self.generation else { return }
            if isDropped {
                search(low: low, high: mid, best: best, generation: generation)
            } else {
                search(low: mid, high: high, best: mid, generation: generation)
            }
        }
    }

    private func finish(with length: CGFloat?) {
        pending = nil
        isMeasuring = false
        generation += 1
        fitted = length.flatMap { $0 >= Self.minimumLength ? $0 : nil }
        startCooldown()
        // Nothing fits: the separator stays normal and hides nothing, rather than sitting long and dropped.
        probe.length = wantsLong ? fitted ?? normalLength : normalLength
        onMeasured?()
    }

    // MARK: checking

    /// Looks once the bar has settled whether the separator is still laid out. A check already waiting covers this one too, so
    /// the windows moving because of the check's own write cannot keep it going.
    private func scheduleCheck() {
        guard fitted != nil, !isChecking else { return }
        isChecking = true
        let generation = generation
        pending = scheduler.schedule(after: Self.settleDelay) { [weak self] in
            guard let self, generation == self.generation else { return }
            pending = nil
            isChecking = false
            guard wantsLong, !isMeasuring, isDropped, cooldown == nil else { return }
            fitted = nil
            measure()
        }
    }

    private var isDropped: Bool {
        guard let baseline else { return true }
        guard let edge = probe.trailingEdge else { return true }
        return edge > baseline + Self.ejectionTolerance
    }

    private func startCooldown() {
        cooldown?.cancel()
        cooldown = scheduler.schedule(after: Self.remeasureCooldown) { [weak self] in self?.cooldown = nil }
    }

    private func stop() {
        generation += 1
        pending?.cancel()
        pending = nil
        isMeasuring = false
        isChecking = false
    }
}
