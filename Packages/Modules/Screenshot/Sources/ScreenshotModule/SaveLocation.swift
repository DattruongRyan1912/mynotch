import Foundation

/// Where "Lưu vào" puts a capture without asking.
nonisolated enum SaveLocation: String, Codable, CaseIterable, Sendable {
    case desktop, downloads, pictures

    var title: String {
        switch self {
        case .desktop: "Desktop"
        case .downloads: "Downloads"
        case .pictures: "Pictures"
        }
    }

    /// The user's folder; reading Desktop or Downloads needs the usage descriptions in the app's Info.plist.
    var standardDirectory: URL? {
        let directory: FileManager.SearchPathDirectory = switch self {
        case .desktop: .desktopDirectory
        case .downloads: .downloadsDirectory
        case .pictures: .picturesDirectory
        }
        return FileManager.default.urls(for: directory, in: .userDomainMask).first
    }
}
