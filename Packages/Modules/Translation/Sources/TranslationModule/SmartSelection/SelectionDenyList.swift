import AppKit
import SwiftUI

/// The apps whose selections are never read, by bundle ID.
nonisolated enum SelectionDenyList {
    static func adding(_ bundleID: String, to list: [String]) -> [String] {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty || list.contains(id) ? list : list + [id]
    }

    static func removing(_ bundleID: String, from list: [String]) -> [String] {
        list.filter { $0 != bundleID }
    }
}

/// Which apps the Settings rows can name and offer.
struct RunningApplications {
    /// An app's name for its bundle ID; the ID itself when no app is installed under it.
    var name: (String) -> String
    /// The ordinary apps running now, by name.
    var running: () -> [(id: String, name: String)]
    /// An app's icon for its bundle ID; nil when no app is installed under it.
    var icon: (String) -> NSImage? = { _ in nil }

    func candidates(excluding denied: [String]) -> [(id: String, name: String)] {
        running().filter { !denied.contains($0.id) }
    }

    static let system = RunningApplications(
        name: { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
        },
        running: {
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
                .compactMap { app in app.bundleIdentifier.map { (id: $0, name: app.localizedName ?? $0) } }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        },
        icon: { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    )
}

/// The rows of "Bôi đen là hiểu": plain rows, since the Settings page provides the Form and the section.
struct SmartSelectionSettingsView: View {
    @Binding var smartSelection: Bool
    @Binding var showChip: Bool
    @Binding var showButton: Bool
    @Binding var showActivity: Bool
    @Binding var denyList: [String]
    let applications: RunningApplications

    static let buttonTitle = "Hiện nút dịch nhỏ khi không tự dịch"

    var body: some View {
        Group {
            Toggle(isOn: $smartSelection) {
                Text("Bôi đen là hiểu")
                Text("Bôi đen chữ ở app nào cũng được: MyNotch tự nhận ra tiền, đơn vị, giờ có múi giờ hay chữ nước ngoài, và cho xem kết quả cạnh vùng chọn. Cần quyền Accessibility. Chữ bạn chọn chỉ xử lý trên máy; bản dịch xem trước chỉ dùng Apple, trên máy, và bộ máy khác chỉ chạy khi bạn bấm “Mở”. Số tiền cần tỷ giá hằng ngày từ internet khi bạn bật “Quy đổi tiền tệ”, không gửi chữ nào. Không đọc ô mật khẩu, app quản lý mật khẩu, đường dẫn, link hay mã. Chrome và app Electron cần mục “Đọc vùng chọn trong Chrome và app Electron” ở dưới đang bật.")
            }
            Toggle(isOn: $showChip) {
                Text("Hiện nút cạnh vùng chọn")
                Text("Một nút nhỏ có kết quả và nút “Mở”. Tự mất sau vài giây, khi bạn bấm chỗ khác hoặc nhấn Esc.")
            }
            .disabled(!Self.optionsEnabled(smartSelection: smartSelection))
            Toggle(isOn: $showButton) {
                Text(Self.buttonTitle)
                Text("Khi MyNotch không tự dịch (tên riêng, tiêu đề, chữ tiếng Việt, câu chưa chắc là tiếng nước ngoài), một nút nhỏ hiện dưới cuối vùng chọn. Bấm vào để dịch như khi nhấn phím tắt. Không hiện cho mã, đường dẫn hay link; bấm chuột phải vào nút để không hiện trong app đó nữa.")
            }
            .disabled(!Self.optionsEnabled(smartSelection: smartSelection))
            Toggle(isOn: $showActivity) {
                Text("Hiện kết quả ở notch thu gọn")
                Text("Kết quả cũng hiện ngắn bên cạnh notch khi đang thu gọn.")
            }
            .disabled(!Self.optionsEnabled(smartSelection: smartSelection))
            LabeledContent("Không hiện trong các app") {
                Menu("Thêm app đang mở…") {
                    let candidates = applications.candidates(excluding: denyList)
                    if candidates.isEmpty {
                        Text("Không còn app nào để thêm")
                    }
                    ForEach(candidates, id: \.id) { app in
                        Button(app.name) { denyList = SelectionDenyList.adding(app.id, to: denyList) }
                    }
                }
                .fixedSize()
            }
            .disabled(!Self.optionsEnabled(smartSelection: smartSelection))
            ForEach(denyList, id: \.self) { id in
                LabeledContent {
                    Button("Bỏ") { denyList = SelectionDenyList.removing(id, from: denyList) }
                } label: {
                    Label {
                        Text(applications.name(id))
                    } icon: {
                        // The app's own icon, small; a plain one when the app is not installed (any more).
                        Image(nsImage: applications.icon(id) ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                }
            }
        }
    }

    /// The options only matter while the feature is on.
    static func optionsEnabled(smartSelection: Bool) -> Bool { smartSelection }
}
