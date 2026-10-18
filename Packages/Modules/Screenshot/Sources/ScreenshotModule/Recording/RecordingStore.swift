import Foundation
import MyNotchCore

/// One line of the list of recordings.
nonisolated struct RecordingSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let folder: URL
    let createdAt: Date
    let duration: TimeInterval
    /// Everything in the folder: the segments, the activity and the project.
    let bytes: Int64
    /// The recording stopped before the person stopped it ("quay dở").
    let isIncomplete: Bool
}

/// The folders of the recordings: `<root>/<uuid>/`, with `root` being `<ModuleStorage.directory>/Recordings`.
nonisolated struct RecordingStore: Sendable {
    let root: URL

    func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// A new, empty folder with a new identity.
    func create() throws -> (id: UUID, folder: URL) {
        let id = UUID()
        let folder = folder(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (id, folder)
    }

    /// Removes the folder of a recording that never got a frame. It is only ever called with a folder this run created and
    /// nothing but its own files in it; a recording with anything recorded is never removed by the engine.
    func discard(id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    /// Removes one recording: its folder, with the segments, the activity and the project, and nothing else. The folder is named by
    /// the ID alone, so no path can lead out of `root`, and a link standing in for it is left alone. False when there was no such
    /// folder or it could not be removed. The caller makes sure the recording is not being made or edited.
    @discardableResult func remove(id: UUID) -> Bool {
        // A trailing slash makes the system follow a link, so the path is used without one.
        var path = folder(for: id).path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let target = URL(filePath: path, directoryHint: .notDirectory)
        let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
        guard type == .typeDirectory else { return false }
        do {
            try FileManager.default.removeItem(at: target)
            return true
        } catch {
            return false
        }
    }

    /// The recordings, newest first. A recording still marked as being recorded that is not in `active` was cut short: it is
    /// rescued first (`RecordingRecovery`), which marks it incomplete. A folder without a readable project is skipped.
    @concurrent func list(excluding active: Set<UUID> = []) async -> [RecordingSummary] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        var summaries: [RecordingSummary] = []
        for name in names {
            guard let id = UUID(uuidString: name) else { continue }
            let folder = folder(for: id)
            guard var project = try? RecordingProject.load(from: folder) else { continue }
            if project.status == .recording, !active.contains(id) {
                guard let rescued = try? await RecordingRecovery.recover(folder: folder) else { continue }
                project = rescued
            }
            summaries.append(RecordingSummary(
                id: id, folder: folder, createdAt: project.createdAt, duration: project.duration,
                bytes: await StorageFolder.bytes(in: folder), isIncomplete: project.isIncomplete
            ))
        }
        return summaries.sorted { $0.createdAt > $1.createdAt }
    }
}
