import AppKit

/// The two lines of the strip under the closed notch at one moment: the one being sung and the one coming next.
struct LyricStrip: Hashable {
    /// Shown dimmed where nothing is sung: before the first line and in the pauses between lines.
    static let note = "\u{266A}"
    /// The strip while the lyrics are not there yet (a new track's are being looked up): the note and an empty second row.
    static let waiting = LyricStrip(current: nil, next: nil)

    /// The line being sung; nil while nothing is, which the strip shows as the note.
    var current: String?
    /// The next line with words; nil after the last one, which leaves the second row empty.
    var next: String?

    init(current: String?, next: String?) {
        self.current = current
        self.next = next
    }

    /// The width of the wider of the two rows as the strip draws them, on one line each: the current row at its size and weight, the next
    /// one at its own, and the note for a current row that is empty. What the notch is asked to be as wide as for it. `measure` gives a
    /// text's width in a font; a line is a point or two wider for a layer that measures a hair more than CoreText does.
    func preferredWidth(measure: (String, NSFont) -> CGFloat = LyricStrip.textWidth) -> CGFloat {
        let current = measure(current ?? Self.note, NowPlayingLyricStrip.currentFont)
        let next = next.map { measure($0, NowPlayingLyricStrip.nextFont) } ?? 0
        return max(current, next) + Self.measuringMargin
    }

    /// What is added to a measured width, so that a line that is exactly as wide as the notch's strip is not cut.
    static let measuringMargin: CGFloat = 2

    /// The width of `text` on one line in `font`.
    nonisolated static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// What VoiceOver reads: the lines, never the note.
    var spoken: String {
        [current, next].compactMap { $0 }.joined(separator: ", ")
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
