import UniformTypeIdentifiers

/// The image formats the shelf writes.
nonisolated enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, heic, tiff

    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    /// "jpg", not the "jpeg" the system prefers, as that is what people name their photos.
    var fileExtension: String { self == .jpeg ? "jpg" : (utType.preferredFilenameExtension ?? rawValue) }

    var label: String { rawValue.uppercased() }

    /// JPEG cannot hold transparency.
    var hasAlpha: Bool { self != .jpeg }

    /// The formats that take the quality setting.
    var isLossy: Bool { self == .jpeg || self == .heic }

    /// The format a file of `type` already has, nil for anything the shelf cannot write (GIF, WebP, BMP…).
    init?(_ type: UTType) {
        guard let format = Self.allCases.first(where: { type.conforms(to: $0.utType) || ($0 == .heic && type.conforms(to: .heif)) }) else { return nil }
        self = format
    }
}

/// How far "Đổi kích thước" shrinks an image.
nonisolated enum ResizePreset: CaseIterable, Sendable {
    case half, side1920, side1280, side800

    var label: String {
        switch self {
        case .half: "50 %"
        case .side1920: "1920 px"
        case .side1280: "1280 px"
        case .side800: "800 px"
        }
    }

    /// Added to the file name: `ảnh-1280.jpg`.
    var suffix: String {
        switch self {
        case .half: "50%"
        case .side1920: "1920"
        case .side1280: "1280"
        case .side800: "800"
        }
    }

    /// The longest side the result has, for an image whose longest side is `side` pixels.
    func longestSide(from side: Int) -> Int {
        switch self {
        case .half: max(1, side / 2)
        case .side1920: 1920
        case .side1280: 1280
        case .side800: 800
        }
    }
}

/// One thing the shelf can do with files.
nonisolated enum FileAction: Equatable, Sendable {
    case convert(ImageFormat)
    case resize(ResizePreset)
    /// To `.jpeg` or `.heic` at the quality setting.
    case compressImage(ImageFormat)
    case zip
    case cutOut
    case readText
    case imagesToPDF
    case pdfToImages

    /// Takes every source together and makes one file, instead of one result per source.
    var combinesSources: Bool { self == .zip || self == .imagesToPDF }

    /// What the progress line and the report call it.
    var title: String {
        switch self {
        case .convert(let format): "Đổi sang \(format.label)"
        case .resize(let preset): "Đổi kích thước \(preset.label)"
        case .compressImage(let format): "Nén ảnh sang \(format.label)"
        case .zip: "Nén thành .zip"
        case .cutOut: "Tách nền"
        case .readText: "Nhận chữ"
        case .imagesToPDF: "Gộp ảnh thành PDF"
        case .pdfToImages: "Tách PDF thành ảnh"
        }
    }
}

/// One entry of the "Hành động" row: a name and the choices behind it.
nonisolated enum ShelfActionGroup: CaseIterable, Sendable {
    case convert, resize, compress, cutOut, readText, pdf

    var title: String {
        switch self {
        case .convert: "Đổi định dạng"
        case .resize: "Đổi kích thước"
        case .compress: "Nén"
        case .cutOut: "Tách nền"
        case .readText: "Nhận chữ"
        case .pdf: "PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .convert: "photo.on.rectangle"
        case .resize: "arrow.down.right.and.arrow.up.left"
        case .compress: "arrow.down.right.and.arrow.up.left.circle"
        case .cutOut: "person.crop.rectangle"
        case .readText: "text.viewfinder"
        case .pdf: "doc.richtext"
        }
    }

    var choices: [(title: String, action: FileAction)] {
        switch self {
        case .convert: ImageFormat.allCases.map { ("Sang \($0.label)", .convert($0)) }
        case .resize: ResizePreset.allCases.map { ($0.label, .resize($0)) }
        case .compress: [("Ảnh sang JPEG", .compressImage(.jpeg)), ("Ảnh sang HEIC", .compressImage(.heic)), ("Thành file .zip", .zip)]
        case .cutOut: [("Tách nền", .cutOut)]
        case .readText: [("Nhận chữ", .readText)]
        case .pdf: [("Gộp ảnh thành một PDF", .imagesToPDF), ("Tách PDF thành ảnh", .pdfToImages)]
        }
    }

    static func containing(_ action: FileAction) -> ShelfActionGroup? {
        allCases.first { $0.choices.contains { $0.action == action } }
    }

    /// What a file dropped on the group runs: the choice used last, else the first. A drop of PDFs on "PDF" splits
    /// them, any other drop there merges.
    func action(preferred: FileAction?, droppingPDFsOnly: Bool) -> FileAction {
        if self == .pdf { return droppingPDFsOnly ? .pdfToImages : .imagesToPDF }
        if let preferred, choices.contains(where: { $0.action == preferred }) { return preferred }
        return choices[0].action
    }
}
