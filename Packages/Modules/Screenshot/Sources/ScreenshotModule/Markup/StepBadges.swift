import CoreGraphics

/// The numbering of the step badges. Each badge stores its number, and every change that removes a badge from the
/// middle goes through `renumbered`, so the numbers always read 1, 2, 3… in the order the badges were placed.
/// Undo needs nothing: it restores the document as it was, numbers included.
nonisolated enum StepBadges {
    /// The number the next badge gets.
    static func nextNumber(in annotations: [Annotation]) -> Int {
        annotations.count(where: isStep) + 1
    }

    /// `annotations` with the badges numbered from 1 in drawing order; other shapes are untouched.
    static func renumbered(_ annotations: [Annotation]) -> [Annotation] {
        var next = 0
        return annotations.map { annotation in
            guard case .step(_, let center, let radius, let color) = annotation else { return annotation }
            next += 1
            return .step(number: next, at: center, radius: radius, color: color)
        }
    }

    /// The index of the badge drawn last that covers `point`, or nil.
    static func indexOfTopmost(at point: CGPoint, in annotations: [Annotation]) -> Int? {
        annotations.lastIndex { annotation in
            guard case .step(_, let center, let radius, _) = annotation else { return false }
            return hypot(point.x - center.x, point.y - center.y) <= radius
        }
    }

    private static func isStep(_ annotation: Annotation) -> Bool {
        if case .step = annotation { true } else { false }
    }
}
