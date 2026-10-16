import SwiftUI

/// The card size and the grid or list choice, in a popover that opens from one button of the library's toolbar. The toolbar used to hold a
/// slider and a segmented switch, and opening the library paid for them every time (about 10 MB that stays resident); a popover's content is
/// made when it is shown and goes when it is dismissed, so none of this exists until the button is pressed.
struct ClipboardLibraryViewOptions: View {
    @Bindable var model: ClipboardLibraryModel

    @FocusState private var focus: Control?

    enum Control: Hashable {
        case layout, size
    }

    /// The stored card size as the slider's position, 0 to 2, rounded and clamped so any position picks a size.
    static func sliderBinding(for model: ClipboardLibraryModel) -> Binding<Double> {
        Binding(
            get: { model.cardSize.sliderValue },
            set: { model.cardSize = ClipboardLibraryCardSize(sliderValue: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Kiểu xem")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Kiểu xem", selection: $model.layout) {
                    Label("Lưới", systemImage: "square.grid.2x2").tag(ClipboardLibraryLayout.grid)
                    Label("Danh sách", systemImage: "list.bullet").tag(ClipboardLibraryLayout.list)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .focused($focus, equals: .layout)
                .help("Lưới hoặc danh sách")
            }
            // Cards have a size; rows have none.
            if model.layout == .grid {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cỡ thẻ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.3x3")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Slider(value: Self.sliderBinding(for: model), in: 0...2, step: 1)
                            .labelsHidden()
                            .focused($focus, equals: .size)
                            .accessibilityLabel("Cỡ thẻ")
                        Image(systemName: "square.grid.2x2")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .help("Cỡ thẻ")
                }
            }
        }
        .padding(14)
        .frame(width: 240)
        // The popover is a window of its own that takes the keyboard: the arrow keys move the control that is focused, and Esc closes it.
        .onAppear { focus = model.layout == .grid ? .size : .layout }
    }
}
