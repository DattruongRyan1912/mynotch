import SwiftUI

/// The Settings rows for the Apple Music account, shown while lyrics are on. Plain rows, like the others.
struct AppleMusicRows: View {
    static let title = "Lời từ Apple Music"
    static let explanation = "Khi kết nối, MyNotch dùng phiên đăng nhập Apple Music của bạn để lấy lời của bài đang phát trong app Music từ máy chủ Apple (API không chính thức, có thể ngừng hoạt động). Token được cất trong Keychain của máy này."
    static let connectTitle = "Kết nối Apple Music…"
    static let disconnectTitle = "Ngắt kết nối"

    let account: AppleMusicAccount
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        Group {
            Text(Self.title).font(.headline)
            Text(Self.explanation).foregroundStyle(.secondary)
            LabeledContent("Trạng thái") {
                Text(account.status.text).foregroundStyle(account.status == .needsReauth ? .orange : .secondary)
            }
            if let problem = account.problem {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Button(Self.connectTitle, action: connect)
                if account.status != .notConnected {
                    Button(Self.disconnectTitle, role: .destructive, action: disconnect)
                }
            }
        }
        // The module reads the Keychain only once it runs; a module switched off still shows the account.
        .onAppear { account.load() }
    }
}
