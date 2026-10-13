import AppKit
import UniformTypeIdentifiers

/// Turns what was dropped on the notch into shelf items.
enum ShelfDropLoader {
    /// A file or folder keeps its place; a web address becomes a link. Anything else that comes as file data (a photo
    /// dragged from Photos or Mail, which the system fulfils as a promise) is copied into its own folder of
    /// `promisedDirectory`. Nil when the provider has nothing usable.
    static func load(_ provider: NSItemProvider, promisedDirectory: URL) async -> ShelfItem.Kind? {
        if provider.canLoadObject(ofClass: URL.self), let url = await object(URL.self, from: provider) {
            return url.isFileURL ? try? .file(at: url) : .link(url)
        }
        if provider.canLoadObject(ofClass: String.self), let text = await object(String.self, from: provider) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(text)
        }
        guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .data) }) else { return nil }
        let folder = promisedDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return await copyRepresentation(of: provider, type: type, into: folder).flatMap { try? .file(at: $0) }
    }

    private static func object<T: _ObjectiveCBridgeable & Sendable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
    where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in continuation.resume(returning: object) }
        }
    }

    /// The provider's temporary file is deleted when the handler returns, so it is copied inside it.
    private static func copyRepresentation(of provider: NSItemProvider, type: UTType, into folder: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let copy = folder.appending(path: url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
