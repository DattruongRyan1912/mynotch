import SwiftUI

struct AboutPage: View {
    private let libraries: [(name: String, license: String, url: String)] = [
        ("KeyboardShortcuts", "MIT", "https://github.com/sindresorhus/KeyboardShortcuts"),
        ("mediaremote-adapter", "BSD-3-Clause", "https://github.com/ungive/mediaremote-adapter"),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent("Phiên bản", value: Bundle.main.shortVersion)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "-")
            }
            Section("Thư viện bên thứ ba") {
                ForEach(libraries, id: \.name) { library in
                    LabeledContent(library.name) {
                        Link(library.license, destination: URL(string: library.url)!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}

private extension Bundle {
    var shortVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
