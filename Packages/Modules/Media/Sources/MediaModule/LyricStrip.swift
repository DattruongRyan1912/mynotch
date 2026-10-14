/// The two lines of the strip under the closed notch at one moment: the one being sung and the one coming next.
struct LyricStrip: Hashable {
    /// Shown dimmed where nothing is sung: before the first line and in the pauses between lines.
    static let note = "\u{266A}"

    /// The line being sung; nil while nothing is, which the strip shows as the note.
    var current: String?
    /// The next line with words; nil after the last one, which leaves the second row empty.
    var next: String?

    init(current: String?, next: String?) {
        self.current = current
        self.next = next
    }

    /// `position` nil is a clock that knows no elapsed time yet: the strip then only shows the note.
    init(lines: [LyricLine], position: Double?) {
        guard let position else {
            self.init(current: nil, next: nil)
            return
        }
        let around = lines.lines(around: position)
        // An empty `current` is a pause between lines.
        self.init(current: around.current.flatMap { $0.text.isEmpty ? nil : $0.text }, next: around.next?.text)
    }
}
