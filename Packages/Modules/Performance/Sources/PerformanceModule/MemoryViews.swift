import NotchUI
import SwiftUI

/// The memory in use as a number and a bar, what the system says about it (pressure, swap, compressed), and the processes that
/// hold the most.
struct MemoryColumn: View {
    static let iconSize: CGFloat = 14

    let state: PerformanceState

    var body: some View {
        let presentation = MemoryPresentation(state.usage)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(presentation.tone?.color ?? NotchTokens.fill(0.3))
                        .frame(width: 7, height: 7)
                    Text("Bộ nhớ")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTokens.secondaryText)
                    Spacer(minLength: 6)
                    Text(presentation.percent)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(NotchTokens.primaryText)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(presentation.used)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NotchTokens.primaryText)
                    Text("/ \(presentation.total)")
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                MemoryBar(fraction: presentation.fraction, tone: presentation.tone)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
            HStack(alignment: .top, spacing: 12) {
                fact(presentation.pressure, "Áp lực")
                fact(presentation.swap, "Swap")
                fact(presentation.compressed, "Nén")
            }
            VStack(spacing: 3) {
                ForEach(state.processes) { ProcessRowView(row: $0) }
            }
        }
        .lineLimit(1)
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(NotchTokens.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct MemoryBar: View {
    let fraction: Double
    let tone: Tone?

    var body: some View {
        let track = NotchTokens.fill(0.18)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tone?.color ?? NotchTokens.accent).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: FanBar.height)
    }
}

/// A process: its icon (a plain glyph when it is not part of an app), its name and what it holds.
struct ProcessRowView: View {
    let row: ProcessRow

    var body: some View {
        HStack(spacing: 6) {
            icon
                .frame(width: MemoryColumn.iconSize, height: MemoryColumn.iconSize)
            Text(row.name)
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.primaryText)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(row.size)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(NotchTokens.secondaryText)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name): \(row.size)")
    }

    @ViewBuilder private var icon: some View {
        if let image = row.icon {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "gearshape")
                .font(.system(size: 10))
                .foregroundStyle(NotchTokens.secondaryText)
        }
    }
}
