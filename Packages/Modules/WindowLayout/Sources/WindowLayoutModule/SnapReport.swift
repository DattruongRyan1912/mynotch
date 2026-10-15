import CoreGraphics
import Foundation

/// The words the module writes about a placement: the lines of the diagnostics log and the notice shown in the notch.
///
/// A log line holds the app's bundle identifier, layout ids and numbers, nothing else: never a window title or anything
/// from inside a window, so the whole line is public in the unified log (subsystem `io.lucasvu.mynotch`, category
/// `window-layout`). Frames are Accessibility coordinates, `x,y,w,h`; sizes are `WxH`; `?` is something the app did not say.
nonisolated enum SnapReport {
    /// What a placement asked for: the layout's zone, or the free part of it beside a neighbour.
    enum Ask: String {
        case zone, part
    }

    /// "<App> không thu nhỏ được tới ô này (tối thiểu 1040 pt)": a window that kept a size bigger than the place it was
    /// given, with the size it needs. Nil when it fits (a size within two points of the zone is rounding).
    static func notice(for app: SnapApp, size: CGSize, zone: CGSize) -> String? {
        let overflow = SnapPlacement.overflow(of: size, in: zone)
        let minimum: String
        switch (overflow.wide, overflow.tall) {
        case (false, false): return nil
        case (true, false): minimum = "\(points(size.width)) pt"
        case (false, true): minimum = "\(points(size.height)) pt chiều cao"
        case (true, true): minimum = "\(points(size.width)) × \(points(size.height)) pt"
        }
        return "\(app.name ?? "Cửa sổ này") không thu nhỏ được tới ô này (tối thiểu \(minimum))"
    }

    /// What was found beside a window about to be placed: how many placed windows are still where they were put, which of
    /// them sit in a neighbouring zone, which of those reach into this one but were skipped because nobody can see them
    /// (minimised, or their app hidden), and what that leaves of the zone.
    static func neighbours(app: SnapApp, target: SnapTarget, known: Int, adjacent: [SnapApp], hidden: [SnapApp], room: SnapRoom) -> String {
        let decision: String
        switch room {
        case .whole: decision = "whole"
        case .part(let free): decision = "part free=\(rect(free.frame))"
        case .crowded: decision = "crowded"
        }
        return "neighbours \(subject(app, target)) known=\(known) adjacent=\(names(adjacent)) hidden=\(names(hidden)) decision=\(decision)"
    }

    /// One placement: what was asked of the window, what it came to and where it went. `oversize` says the window kept a
    /// size bigger than what was asked (it overlaps whatever is beside the part it was given); `refused`, that the app
    /// would not move it. A refused window's size says nothing.
    static func placed(app: SnapApp, target: SnapTarget, ask: Ask, placement: SnapPlacement, actual: CGRect?, moved: Bool) -> String {
        let origin = actual.map { point(placement.origin(for: $0.size)) } ?? "?"
        let oversize = moved && (actual.map { placement.isOversize($0.size) } ?? false)
        return "placed \(subject(app, target)) ask=\(ask.rawValue) frame=\(rect(placement.frame)) requested=\(size(placement.frame.size))"
            + " actual=\(actual.map { size($0.size) } ?? "?") origin=\(origin) landed=\(actual.map { point($0.origin) } ?? "?")"
            + " oversize=\(oversize ? "yes" : "no") refused=\(moved ? "no" : "yes")"
    }

    /// The placed window ended up over another one. The other window is never moved to make room.
    static func overlaps(app: SnapApp, other: PlacedWindows.Placed, by overlap: CGSize) -> String {
        "overlaps app=\(app.bundleID ?? "?") with=\(other.app.bundleID ?? "?") layout=\(other.target.layout.id) zone=\(other.target.zone)"
            + " by=\(size(overlap)) neighbour-moved=no"
    }

    private static func names(_ apps: [SnapApp]) -> String {
        apps.isEmpty ? "none" : apps.map { $0.bundleID ?? "?" }.joined(separator: "+")
    }

    private static func subject(_ app: SnapApp, _ target: SnapTarget) -> String {
        "app=\(app.bundleID ?? "?") layout=\(target.layout.id) zone=\(target.zone)"
    }

    private static func rect(_ rect: CGRect) -> String {
        "\(number(rect.minX)),\(number(rect.minY)),\(number(rect.width)),\(number(rect.height))"
    }

    private static func point(_ point: CGPoint) -> String { "\(number(point.x)),\(number(point.y))" }

    private static func size(_ size: CGSize) -> String { "\(number(size.width))x\(number(size.height))" }

    private static func points(_ value: CGFloat) -> Int { Int(value.rounded()) }

    /// Whole points as they are, anything else with one decimal.
    private static func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", Double(value))
    }
}
