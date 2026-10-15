/// The three lines of the floating panel at one moment: the one before, the one being sung and the one coming next. Pauses are
/// never lines, so a pause leaves `current` nil, with the line just sung before it.
nonisolated struct LyricPanelLines: Equatable, Sendable {
    var previous: LyricLine?
    var current: LyricLine?
    var next: LyricLine?

    /// What VoiceOver reads: the lines, never the note.
    var spoken: String {
        [previous, current, next].compactMap { $0?.text }.joined(separator: ", ")
    }

    /// `position` nil is a clock that knows no elapsed time yet: nothing is shown then.
    init(lines: [LyricLine], position: Double?) {
        guard let position, let index = lines.indexOfLine(at: position) else {
            previous = nil
            current = nil
            // Before the first line only the first line with words is coming.
            next = position == nil ? nil : lines.first { !$0.text.isEmpty }
            return
        }
        let isPause = lines[index].text.isEmpty
        current = isPause ? nil : lines[index]
        previous = lines[..<(isPause ? index + 1 : index)].last { !$0.text.isEmpty }
        next = lines[(index + 1)...].first { !$0.text.isEmpty }
    }
}
