/// The keys held during a drag that change what a tool does: ⇧ snaps the ruler, ⌥ deletes a step badge.
nonisolated struct MarkupModifiers: OptionSet, Sendable {
    let rawValue: Int

    static let shift = MarkupModifiers(rawValue: 1)
    static let option = MarkupModifiers(rawValue: 2)
}
