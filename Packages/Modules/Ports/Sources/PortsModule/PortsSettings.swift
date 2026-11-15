import SwiftUI

/// Plain rows: the Settings page provides the Form and the section.
struct PortsSettingsView: View {
    let showUDP: Binding<Bool>

    var body: some View {
        Toggle(isOn: showUDP) {
            Text("Hiện cả cổng UDP")
            Text("Mặc định chỉ hiện cổng TCP đang lắng nghe. UDP thường có nhiều cổng của trình duyệt và dịch vụ hệ thống.")
        }
    }
}
