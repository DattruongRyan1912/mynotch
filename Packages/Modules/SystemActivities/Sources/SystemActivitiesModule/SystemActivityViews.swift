import MyNotchCore
import SwiftUI

extension SystemActivityContent {
    /// Both sides are kept within 64 pt.
    func liveActivity(duration: Duration) -> LiveActivity {
        let tint: Color = priority >= .high ? .red : .white
        return LiveActivity(
            id: id, priority: priority, expiresAfter: expires ? duration : nil,
            leading: AnyView(SystemActivityGlyph(glyph: glyph, tint: tint)),
            trailing: AnyView(SystemActivityTrailing(trailing: trailing, tint: tint)))
    }
}

struct SystemActivityGlyph: View {
    let glyph: SystemActivityContent.Glyph
    let tint: Color

    var body: some View {
        Group {
            switch glyph {
            case .symbol(let name): Image(systemName: name)
            case .text(let text): Text(text)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(tint)
        .frame(maxWidth: 64)
    }
}

struct SystemActivityTrailing: View {
    let trailing: SystemActivityContent.Trailing
    let tint: Color

    var body: some View {
        switch trailing {
        case .text(let text):
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: 64)
        case .level(let level):
            LevelBar(level: level, tint: tint).frame(width: 40, height: 4)
        }
    }
}

private struct LevelBar: View {
    let level: Float
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.25))
                Capsule().fill(tint).frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
    }
}
