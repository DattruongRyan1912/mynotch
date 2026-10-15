import SwiftUI

/// How the spectrum bars are coloured: from the cover, white, or a gradient between two colours the user picks.
struct SpectrumColorRows: View {
    static let title = "Màu phổ âm thanh"
    static let startTitle = "Màu đầu"
    static let endTitle = "Màu cuối"
    static let tintOffNote = "Đang tắt “\(MediaSettingsView.tintTitle)”, nên cột sóng giữ màu mặc định."

    @Binding var mode: SpectrumColorMode
    @Binding var start: SRGBColor
    @Binding var end: SRGBColor
    /// "Màu theo ảnh bìa" is on; the cover's mode has nothing to follow without it.
    let tintIsOn: Bool

    static func showsGradientPickers(for mode: SpectrumColorMode) -> Bool { mode == .gradient }

    /// Why a choice has no effect, nil when it does.
    static func note(for mode: SpectrumColorMode, tintIsOn: Bool) -> String? {
        mode == .artwork && !tintIsOn ? tintOffNote : nil
    }

    var body: some View {
        Picker(selection: $mode) {
            ForEach(SpectrumColorMode.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            Text(Self.title)
            if let note = Self.note(for: mode, tintIsOn: tintIsOn) { Text(note) }
        }
        if Self.showsGradientPickers(for: mode) {
            ColorPicker(Self.startTitle, selection: picker($start), supportsOpacity: false)
            ColorPicker(Self.endTitle, selection: picker($end), supportsOpacity: false)
        }
    }

    private func picker(_ color: Binding<SRGBColor>) -> Binding<Color> {
        Binding(get: { color.wrappedValue.color }, set: { color.wrappedValue = SRGBColor($0) })
    }
}
