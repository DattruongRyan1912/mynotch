import CoreGraphics
import CoreText
import Foundation

/// The numbered badge and the ruler: vector shapes with text, drawn in the same y-down pixel space as the others.
nonisolated extension MarkupRenderer {
    /// A disc with a thin light rim and its number in whichever of black and white reads better on the colour.
    static func drawStep(number: Int, center: CGPoint, radius: CGFloat, color: RGBAColor, in context: CGContext) {
        guard radius > 0 else { return }
        let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: disc)
        let rim = max(1, radius * 0.12)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
        context.setLineWidth(rim)
        context.strokeEllipse(in: disc.insetBy(dx: rim / 2, dy: rim / 2))
        let digits = String(number).count
        let fontSize = radius * (digits <= 1 ? 1.1 : digits == 2 ? 0.95 : 0.75)
        drawCenteredText(String(number), at: center, fontSize: fontSize, color: color.prefersDarkText ? .black : RGBAColor(r: 1, g: 1, b: 1), in: context)
    }

    /// The line with a short stroke across each end, and the distance in a pill beside it.
    static func drawRuler(from start: CGPoint, to end: CGPoint, style: Annotation.StrokeStyle, fontSize: CGFloat, scale: CGFloat, in context: CGContext) {
        guard start != end else { return }
        let layout = Ruler.layout(from: start, to: end, lineWidth: style.width, fontSize: fontSize, scale: scale)
        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(style.width)
        context.setLineCap(.round)
        context.strokeLineSegments(between: [start, end] + layout.ticks.flatMap { [$0.0, $0.1] })
        let corner = layout.labelRect.height / 2
        context.setFillColor(style.color.cgColor)
        context.addPath(CGPath(roundedRect: layout.labelRect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
        let center = CGPoint(x: layout.labelRect.midX, y: layout.labelRect.midY)
        drawCenteredText(layout.label, at: center, fontSize: fontSize, color: style.color.prefersDarkText ? .black : RGBAColor(r: 1, g: 1, b: 1), in: context)
    }

    /// One line of text centred on `center`: by its glyphs across, and by the font's ascent and descent down, so a
    /// label does not hop when its characters change.
    private static func drawCenteredText(_ string: String, at center: CGPoint, fontSize: CGFloat, color: RGBAColor, in context: CGContext) {
        let font = textFont(fontSize)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: textAttributes(font, color)))
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let textMatrix = context.textMatrix
        defer { context.textMatrix = textMatrix }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: center.x - glyphs.midX, y: center.y + (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)
        CTLineDraw(line, context)
    }
}
