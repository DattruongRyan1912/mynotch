import CoreGraphics
import Foundation

/// Runs one action on files. It holds no state, so any number of runs can use one, and its work is off the main
/// actor. Every result is written next to its source under a name that is not taken, and a failed or cancelled
/// action leaves nothing behind.
nonisolated struct FileActionProcessor: Sendable {
    var recognizer: any TextRecognizing = VisionTextRecognizer()
    var cutter: any ForegroundCutting = VisionForegroundCutter()
    /// For JPEG, HEIC and the images inside a PDF.
    var quality = 0.85
    /// Whether the GPS metadata of an image is left out of what is written.
    var stripLocation = true
    var folders = OutputFolders(promisedDirectory: nil)
    /// Where a zip copies files to before it zips them.
    var stagingRoot = FileManager.default.temporaryDirectory
    /// Adds links to a finished zip; a seam for tests of what happens when the archive cannot take them.
    var storeLinks: @Sendable ([ZipLink], URL) throws -> Void = { try ZipLinks.append($0, to: $1) }

    /// What an action made of one source: the files it wrote, or the text it read.
    struct Output: Sendable {
        var files: [URL] = []
        var text: String?
    }

    /// What an action made of several sources together.
    struct Combined: Sendable {
        let files: [URL]
        let skipped: [SkippedFile]
    }

    /// The actions that make something from each source on its own. `progress` hears how far a long one is (0 to 1).
    @concurrent
    func process(_ action: FileAction, source: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Output {
        switch action {
        case .convert(let format): try convert(source, to: format)
        case .resize(let preset): try resize(source, preset)
        case .compressImage(let format): try compress(source, to: format)
        case .cutOut: try await cutOut(source)
        case .readText: try await readText(source)
        case .pdfToImages:
            Output(files: try PDFActions.renderPages(of: source, folders: folders) { written, total in progress(Double(written) / Double(total)) })
        case .zip, .imagesToPDF:
            assertionFailure("\(action) takes its sources together: use combine")
            throw FileActionError.unreadable
        }
    }

    /// The actions that make one file of all their sources.
    @concurrent
    func combine(_ action: FileAction, sources: [URL]) async throws -> Combined {
        switch action {
        case .zip:
            let present = sources.filter(ZipArchive.exists)
            guard !present.isEmpty else { throw FileActionError.missing }
            let made = try ZipArchive.make(from: present, folders: folders, stagingRoot: stagingRoot, storeLinks: storeLinks)
            // One row for all the links left out: a tree can hold thousands.
            let skipped = sources.filter { !present.contains($0) }.map { SkippedFile(source: $0, error: .missing) }
                + (made.unstoredLinks.isEmpty ? [] : [SkippedFile(source: made.file, error: .linksNotStored(count: made.unstoredLinks.count))])
            return Combined(files: [made.file], skipped: skipped)
        case .imagesToPDF:
            let merged = try PDFActions.makePDF(from: sources, quality: quality, folders: folders)
            return Combined(files: [merged.file], skipped: merged.skipped)
        default:
            assertionFailure("\(action) works on one source at a time: use process")
            throw FileActionError.unreadable
        }
    }

    // MARK: Images

    private func convert(_ source: URL, to format: ImageFormat) throws -> Output {
        let loaded = try ImageCodec.load(source, longestSide: nil)
        guard loaded.format != format else { throw FileActionError.alreadyFormat(format) }
        return try write(loaded, as: format, for: source, suffix: nil)
    }

    private func resize(_ source: URL, _ preset: ResizePreset) throws -> Output {
        let size = try ImageCodec.uprightSize(of: source)
        let longest = Int(max(size.width, size.height))
        let target = preset.longestSide(from: longest)
        guard target < longest else { throw FileActionError.notSmaller }
        let loaded = try ImageCodec.load(source, longestSide: target)
        return try write(loaded, as: loaded.format ?? .png, for: source, suffix: preset.suffix)
    }

    private func compress(_ source: URL, to format: ImageFormat) throws -> Output {
        try write(try ImageCodec.load(source, longestSide: nil), as: format, for: source, suffix: "nén")
    }

    private func cutOut(_ source: URL) async throws -> Output {
        let loaded = try ImageCodec.load(source, longestSide: nil)
        try Task.checkCancellation()
        let cut = try await failing(with: .cutOutFailed) { try await cutter.cutOut(loaded.image) }
        // The cut-out is a new picture: nothing of the original's metadata goes with it.
        let data = try ImageCodec.encode(cut, as: .png, quality: 1, properties: [:], stripLocation: true)
        return Output(files: [try place(data, for: source, suffix: "không-nền", ext: ImageFormat.png.fileExtension)])
    }

    private func readText(_ source: URL) async throws -> Output {
        let loaded = try ImageCodec.load(source, longestSide: nil)
        try Task.checkCancellation()
        let text = try await failing(with: .recognitionFailed) {
            try await recognizer.recognize(loaded.image, languages: VisionTextRecognizer.languages)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw FileActionError.noText }
        return Output(text: text)
    }

    private func write(_ loaded: ImageCodec.Loaded, as format: ImageFormat, for source: URL, suffix: String?) throws -> Output {
        try Task.checkCancellation()
        let data = try ImageCodec.encode(loaded.image, as: format, quality: quality, properties: loaded.properties, stripLocation: stripLocation)
        return Output(files: [try place(data, for: source, suffix: suffix, ext: format.fileExtension)])
    }

    private func place(_ data: Data, for source: URL, suffix: String?, ext: String) throws -> URL {
        try Task.checkCancellation()
        return try OutputNaming.place(
            stem: source.deletingPathExtension().lastPathComponent, suffix: suffix, ext: ext, in: folders.folder(for: source)
        ) { try data.write(to: $0, options: .withoutOverwriting) }
    }

    /// Runs work that belongs to something else (Vision, a fake): its errors become `failure`, apart from
    /// cancellation and the action's own errors.
    private func failing<T>(with failure: FileActionError, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as FileActionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw failure
        }
    }
}
