import CoreGraphics
import MyNotchCore

/// What the chip beside a new capture shows and what its buttons do. The window only draws it; the module hands it these.
struct CaptureChipContent {
    /// The capture's thumbnail, nil when it could not be made.
    let thumbnail: CGImage?
    /// "Sửa". Never run by anything but the user pressing the button.
    let edit: @MainActor () -> Void
    /// "Chép".
    let copy: @MainActor () -> Void
    /// "Ghim".
    let pin: @MainActor () -> Void
    /// The pointer came onto the chip (true) or left it (false).
    let hover: @MainActor (Bool) -> Void

    init(
        thumbnail: CGImage?,
        edit: @escaping @MainActor () -> Void,
        copy: @escaping @MainActor () -> Void,
        pin: @escaping @MainActor () -> Void = {},
        hover: @escaping @MainActor (Bool) -> Void
    ) {
        self.thumbnail = thumbnail
        self.edit = edit
        self.copy = copy
        self.pin = pin
        self.hover = hover
    }
}

/// Where the chip appears; a protocol so tests never put a window on a screen.
protocol CaptureChipPresenting: AnyObject {
    /// Puts the chip up, or replaces the one that is.
    func show(_ content: CaptureChipContent)
    func hide()
}

/// The chip's life: it stays six seconds, or as long as the pointer is on it and until the pointer leaves, and goes at
/// once when a button is pressed or the module takes it away. Time comes from the module's scheduler, so tests move it.
final class CaptureChipController {
    static let lifetime: Duration = .seconds(6)

    private let presenter: any CaptureChipPresenting
    private let scheduler: any Scheduler
    private var timer: ScheduledAction?
    /// The pointer has been on this chip, so leaving it is a reason to hide it.
    private var isHovered = false
    private(set) var isShown = false

    init(presenter: any CaptureChipPresenting, scheduler: any Scheduler) {
        self.presenter = presenter
        self.scheduler = scheduler
    }

    /// Shows a chip for a capture, replacing any earlier one and starting the clock again.
    func show(
        thumbnail: CGImage?,
        edit: @escaping @MainActor () -> Void,
        copy: @escaping @MainActor () -> Void,
        pin: @escaping @MainActor () -> Void = {}
    ) {
        timer?.cancel()
        isHovered = false
        isShown = true
        presenter.show(CaptureChipContent(
            thumbnail: thumbnail,
            edit: { [weak self] in
                self?.hide()
                edit()
            },
            copy: { [weak self] in
                self?.hide()
                copy()
            },
            pin: { [weak self] in
                self?.hide()
                pin()
            },
            hover: { [weak self] in self?.hover($0) }
        ))
        timer = scheduler.schedule(after: Self.lifetime) { [weak self] in self?.hide() }
    }

    func hide() {
        timer?.cancel()
        timer = nil
        isHovered = false
        guard isShown else { return }
        isShown = false
        presenter.hide()
    }

    /// While the pointer is on the chip it does not time out; once it has been there and leaves, the chip goes.
    private func hover(_ isInside: Bool) {
        guard isShown else { return }
        if isInside {
            isHovered = true
            timer?.cancel()
            timer = nil
        } else if isHovered {
            hide()
        }
    }
}
