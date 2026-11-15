/// What fills the canvas where it grew past the capture. "Settings → Screenshot" picks one.
nonisolated enum CanvasFill: String, Codable, CaseIterable, Sendable {
    case transparent, white, black
    /// The most common colour along the capture's outermost pixels, so the padding blends into a window's background.
    case edgeColor

    static let standard = CanvasFill.edgeColor

    var title: String {
        switch self {
        case .transparent: "Trong suốt"
        case .white: "Trắng"
        case .black: "Đen"
        case .edgeColor: "Màu viền ảnh"
        }
    }
}
