import AppKit
import SwiftUI

struct AboutPage: View {
    private let libraries: [(name: String, license: String, url: String)] = [
        ("KeyboardShortcuts", "MIT", "https://github.com/sindresorhus/KeyboardShortcuts"),
        ("mediaremote-adapter", "BSD-3-Clause", "https://github.com/ungive/mediaremote-adapter"),
    ]

    var body: some View {
        Form {
            // App Identity Header (Apple Style)
            Section {
                VStack(spacing: 12) {
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }

                    VStack(spacing: 3) {
                        Text("MyNotch")
                            .font(.system(size: 18, weight: .bold))

                        Text("Tiện ích mở rộng vùng Notch thông minh cho macOS")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("Phiên bản \(Bundle.main.shortVersion)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Thông tin ứng dụng") {
                LabeledContent("Phiên bản", value: Bundle.main.shortVersion)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "-")
                LabeledContent("Nhà phát triển", value: "Ryan Truong")
            }

            Section("Thư viện mã nguồn mở") {
                ForEach(libraries, id: \.name) { library in
                    LabeledContent(library.name) {
                        Link(library.license, destination: URL(string: library.url)!)
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private extension Bundle {
    var shortVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
