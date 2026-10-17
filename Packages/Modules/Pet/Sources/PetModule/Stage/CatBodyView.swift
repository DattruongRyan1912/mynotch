import AppKit
import NotchUI
import SwiftUI

/// Where the cat plays on a notch, and what the notch is asked for it.
nonisolated struct CatBodyLayout: Equatable, Sendable {
    /// The room asked for on each side of a hardware notch's camera: the width of the notch's top row is the camera's and twice this.
    static let wingRoom: CGFloat = 100
    /// The width asked of a virtual notch's body, which is wider than the narrowest of them is and no wider than the widest is without it.
    static let virtualWidth: CGFloat = 280

    let kind: NotchKind
    let place: PlayPlace

    /// Whether the cat plays in the top row of this notch: always on one with no camera (a strip under a virtual notch is a waste of its
    /// height, with room in the body), and on one with a camera unless the user chose the strip.
    var playsInBody: Bool { kind == .virtual || place == .portal }

    /// How wide the top row is asked to be, from the camera's width on a hardware notch.
    func requestedWidth(cameraWidth: CGFloat) -> CGFloat {
        kind == .hardware ? cameraWidth + 2 * Self.wingRoom : Self.virtualWidth
    }
}

/// The cat in the top row of the notch, in place of the strip: on a virtual notch one lane across the body, on a hardware one two lanes,
/// one each side of the camera, which the cat goes from one to the other of through a portal.
struct CatBodyView: View {
    let stage: CatStage
    let place: PlayPlace
    @Environment(\.notchGeometry) private var geometry
    @Environment(\.notchIsOnScreen) private var isOnScreen

    var body: some View {
        let layout = CatBodyLayout(kind: geometry?.kind ?? .virtual, place: place)
        if isOnScreen, layout.playsInBody {
            CatBody(stage: stage, geometry: geometry)
                .notchBodyWidth(layout.requestedWidth(cameraWidth: geometry?.notchSize.width ?? 0))
        } else {
            Color.clear
        }
    }
}

struct CatBody: NSViewRepresentable {
    let stage: CatStage
    let geometry: NotchGeometry?

    func makeNSView(context: Context) -> CatBodyContainer { CatBodyContainer(stage: stage) }

    func updateNSView(_ view: CatBodyContainer, context: Context) { view.configure(geometry: geometry) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: CatBodyContainer, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 300, height: 32))
    }
}

/// Where the camera is in the top row of a hardware notch, as a stretch of the row from the left.
nonisolated enum Cutout {
    /// From the geometry: the notch's body is as wide as the camera's cutout and in the middle of the row, which is as wide as the notch.
    static func geometric(rowWidth: CGFloat, cameraWidth: CGFloat) -> ClosedRange<CGFloat> {
        let low = max((rowWidth - cameraWidth) / 2, 0)
        return low...max(low + cameraWidth, low)
    }

    /// From the screen's own: between the right edge of the area of the menu bar left of the camera and the left edge of the one right of
    /// it, in screen coordinates. Nil for a screen with no camera.
    static func measured(auxiliaryLeft: CGRect?, auxiliaryRight: CGRect?) -> ClosedRange<CGFloat>? {
        guard let auxiliaryLeft, let auxiliaryRight, auxiliaryRight.minX > auxiliaryLeft.maxX else { return nil }
        return auxiliaryLeft.maxX...auxiliaryRight.minX
    }
}

/// The view that holds the cat's views in the top row of one notch: one across the body of a virtual notch, two (left and right of the
/// camera) on a hardware one. It takes a click only where one of them has the cat.
final class CatBodyContainer: NSView {
    private(set) weak var stage: CatStage?
    private var geometry: NotchGeometry?
    private(set) var lane: CatSpriteView?
    private(set) var leftWing: CatSpriteView?
    private(set) var rightWing: CatSpriteView?
    /// The areas of the menu bar either side of the camera, in screen coordinates, on the screen `window` is on: the screen's own. A test
    /// says where they are.
    var screenAreas: (NSWindow) -> (left: CGRect?, right: CGRect?)? = { window in
        window.screen.map { ($0.auxiliaryTopLeftArea, $0.auxiliaryTopRightArea) }
    }

    init(stage: CatStage) {
        self.stage = stage
        super.init(frame: .zero)
        // The views it holds draw on layers, and a layer under them that is a layer of its own is what Core Animation does anyway.
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The views the cat is shown in.
    var catViews: [CatSpriteView] { [lane, leftWing, rightWing].compactMap { $0 } }

    private var kind: NotchKind { geometry?.kind ?? .virtual }

    func configure(geometry: NotchGeometry?) {
        self.geometry = geometry
        arrange()
        needsLayout = true
    }

    /// One lane for a notch with no camera and a pair of wings for one with: the views are made again when the kind changes (a change of
    /// the setting does not, but a view that moves to another kind of display does).
    private func arrange() {
        let wantsWings = kind == .hardware
        guard wantsWings ? lane != nil || leftWing == nil : leftWing != nil || lane == nil else { return }
        catViews.forEach { $0.removeFromSuperview() }
        (lane, leftWing, rightWing) = (nil, nil, nil)
        guard let stage else { return }
        if wantsWings {
            let (left, right) = (CatSpriteView(stage: stage, role: .leftWing), CatSpriteView(stage: stage, role: .rightWing))
            left.partner = right
            right.partner = left
            (leftWing, rightWing) = (left, right)
            [left, right].forEach(addSubview)
        } else {
            let view = CatSpriteView(stage: stage, role: .lane)
            lane = view
            addSubview(view)
        }
    }

    /// Where the camera is in this view's own coordinates: as the screen reports it when this view is on one with a camera, else as the
    /// geometry says.
    func cutout() -> ClosedRange<CGFloat> {
        if let window, let areas = screenAreas(window),
           let range = Cutout.measured(auxiliaryLeft: areas.left, auxiliaryRight: areas.right) {
            let onScreen = CGRect(x: range.lowerBound, y: window.frame.minY, width: range.upperBound - range.lowerBound, height: 1)
            let local = convert(window.convertFromScreen(onScreen), from: nil)
            let low = min(max(local.minX, 0), bounds.width)
            return low...min(max(local.maxX, low), bounds.width)
        }
        return Cutout.geometric(rowWidth: bounds.width, cameraWidth: geometry?.notchSize.width ?? 0)
    }

    override func layout() {
        super.layout()
        if let lane {
            lane.frame = bounds
        } else if let leftWing, let rightWing {
            let camera = cutout()
            leftWing.frame = CGRect(x: 0, y: 0, width: camera.lowerBound.rounded(), height: bounds.height)
            rightWing.frame = CGRect(x: camera.upperBound.rounded(), y: 0, width: max(bounds.width - camera.upperBound.rounded(), 0), height: bounds.height)
        }
        for view in catViews { stage?.hostDidMove(view) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for view in catViews.reversed() {
            if let hit = view.hitTest(local) { return hit }
        }
        return nil
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
