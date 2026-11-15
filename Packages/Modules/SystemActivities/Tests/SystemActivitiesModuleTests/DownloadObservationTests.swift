import Foundation
import Testing
@testable import SystemActivitiesModule

@Suite struct DownloadObservationTests {
    func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyNotchTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func readsSizeAndMissingFiles() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data(repeating: 1, count: 12).write(to: file)

        let seen = FileObservation.read(file, flags: .created)
        #expect(seen.size == 12)
        #expect(!seen.hasOrigin)
        #expect(!seen.isDirectory)
        #expect(seen.flags == .created)
        #expect(abs(seen.date.timeIntervalSinceNow) < 60)

        try FileManager.default.removeItem(at: file)
        #expect(FileObservation.read(file, flags: [.created, .modified]).flags == .removed)
    }

    @Test func detectsDownloadOriginAttributes() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data([1]).write(to: file)
        #expect(!FileObservation.read(file, flags: .created).hasOrigin)
        let value = Array("0083;00000000;Safari;".utf8)
        #expect(setxattr(file.path, "com.apple.quarantine", value, value.count, 0, 0) == 0)
        #expect(FileObservation.read(file, flags: .created).hasOrigin)
    }

    @Test func readsDirectories() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(FileObservation.read(dir, flags: .created).isDirectory)
    }
}
