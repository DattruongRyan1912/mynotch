import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct RecordingProjectTests {
    static let region = RecordingRegion(fullScreen: DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 60), scale: 2))!

    func project(
        _ id: UUID = UUID(), created: Double = 1_000, status: RecordingProject.Status = .finished, durations: [TimeInterval] = [3, 4]
    ) -> RecordingProject {
        RecordingProject(
            id: id, createdAt: Date(timeIntervalSince1970: created), status: status, region: Self.region, fps: 60,
            hasMicrophone: true, hasSystemAudio: false,
            segments: durations.enumerated().map { .init(fileName: "segment-\(String(format: "%03d", $0.offset + 1)).mov", captureStart: 50 + Double($0.offset) * 10, duration: $0.element, frames: 10) }
        )
    }

    @Test func aProjectIsWrittenAndReadBackWithEverythingInIt() throws {
        let folder = try TestFolder("project")
        let original = project()

        try original.write(to: folder.url)

        #expect(try RecordingProject.load(from: folder.url) == original)
        #expect(original.duration == 7)
        #expect(!original.isIncomplete)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["project.json"])
    }

    @Test func aFileMissingTheFieldsALaterVersionAddsStillOpensWithDefaults() throws {
        let folder = try TestFolder("project")
        let id = UUID()
        let region = try JSONEncoder().encode(Self.region)
        let json = """
        {"id":"\(id.uuidString)","createdAt":"2026-10-18T08:00:00Z","status":"finished","region":\(String(decoding: region, as: UTF8.self)),
         "someFieldFromTheFuture":{"zoom":[1,2,3]},
         "segments":[{"fileName":"segment-001.mov","duration":2.5}]}
        """
        try Data(json.utf8).write(to: folder.file("project.json"))

        let project = try RecordingProject.load(from: folder.url)

        #expect(project.id == id && project.fps == 60 && !project.hasMicrophone && !project.hasSystemAudio)
        #expect(project.segments == [.init(fileName: "segment-001.mov", captureStart: nil, duration: 2.5)])
        #expect(project.version == 1)
        // None of what editing adds was in the file: nothing is cut, the zooms are still to be planned, the rings are on.
        #expect(project.cuts.isEmpty && project.zoomRules == .standard && project.zoomSegments == nil && project.clickEffect)
    }

    @Test func everyEditIsWrittenAndReadBackWithValuesThatAreNotTheDefaults() throws {
        let folder = try TestFolder("project")
        var original = project()
        original.cuts = [CutRange(start: 1.5, end: 2.25), CutRange(start: 5, end: 6.5)]
        original.zoomRules = ZoomRules()
        original.zoomRules.scale = 2.75
        original.zoomRules.zoomInDuration = 0.8
        original.zoomRules.zoomOutDuration = 0.9
        original.zoomRules.idleTimeout = 2.25
        original.zoomRules.mergeGap = 4
        original.zoomRules.minimumMovement = 11
        original.zoomSegments = [
            ZoomSegment(start: 1, end: 4, scale: 1.5, focus: [.init(t: 1, x: 10.5, y: 20.25), .init(t: 2.5, x: 300, y: 40)], manual: true),
            ZoomSegment(start: 5, end: 6, scale: 3),
        ]
        original.clickEffect = false

        try original.write(to: folder.url)
        let loaded = try RecordingProject.load(from: folder.url)

        #expect(loaded == original)
        #expect(loaded.cuts == [CutRange(start: 1.5, end: 2.25), CutRange(start: 5, end: 6.5)])
        #expect(loaded.zoomRules.scale == 2.75 && loaded.zoomRules.zoomInDuration == 0.8 && loaded.zoomRules.zoomOutDuration == 0.9)
        #expect(loaded.zoomRules.idleTimeout == 2.25 && loaded.zoomRules.mergeGap == 4 && loaded.zoomRules.minimumMovement == 11)
        #expect(loaded.zoomSegments?.count == 2 && loaded.zoomSegments?[0].manual == true && loaded.zoomSegments?[0].focus.count == 2)
        #expect(loaded.clickEffect == false)
    }

    @Test func zoomsNotYetEditedAndZoomsAllRemovedAreNotTheSameThing() throws {
        let folder = try TestFolder("project")
        var project = project()

        project.zoomSegments = nil
        try project.write(to: folder.url)
        #expect(try RecordingProject.load(from: folder.url).zoomSegments == nil)

        project.zoomSegments = []
        try project.write(to: folder.url)
        #expect(try RecordingProject.load(from: folder.url).zoomSegments == [])
    }

    @Test func zoomFieldsAFileLacksAreFilledInWithTheirDefaults() throws {
        let folder = try TestFolder("project")
        let region = try JSONEncoder().encode(Self.region)
        let json = """
        {"id":"\(UUID().uuidString)","createdAt":"2026-10-18T08:00:00Z","status":"finished","region":\(String(decoding: region, as: UTF8.self)),
         "zoomRules":{"scale":3},"zoomSegments":[{"start":1,"end":2,"scale":2}],"cuts":[{"start":0,"end":1}],"segments":[]}
        """
        try Data(json.utf8).write(to: folder.file("project.json"))

        let project = try RecordingProject.load(from: folder.url)

        #expect(project.zoomRules.scale == 3 && project.zoomRules.zoomInDuration == 0.5 && project.zoomRules.mergeGap == 2.5)
        #expect(project.zoomSegments == [ZoomSegment(start: 1, end: 2, scale: 2)])
        #expect(project.zoomSegments?[0].manual == false && project.zoomSegments?[0].focus.isEmpty == true)
        #expect(project.cuts == [CutRange(start: 0, end: 1)])
    }

    @Test func aFileWithoutItsIdentityDoesNotOpen() throws {
        let folder = try TestFolder("project")
        try Data(#"{"status":"finished"}"#.utf8).write(to: folder.file("project.json"))

        #expect(throws: (any Error).self) { try RecordingProject.load(from: folder.url) }
    }
}

@Suite struct RecordingStoreTests {
    let folder: TestFolder
    let store: RecordingStore

    init() throws {
        folder = try TestFolder("store")
        store = RecordingStore(root: folder.file("Recordings"))
    }

    /// A recording folder with a project and `fileBytes` bytes of segment, as a finished recording looks.
    @discardableResult
    func make(created: Double, status: RecordingProject.Status = .finished, fileBytes: Int = 1_000, durations: [TimeInterval] = [3]) throws -> RecordingProject {
        let (id, directory) = try store.create()
        let project = RecordingProjectTests().project(id, created: created, status: status, durations: durations)
        try project.write(to: directory)
        try Data(count: fileBytes).write(to: directory.appending(path: "segment-001.mov"))
        return project
    }

    func bytes(of project: RecordingProject) -> Int64 {
        let directory = store.folder(for: project.id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.reduce(0) { total, name in
            total + Int64((try? FileManager.default.attributesOfItem(atPath: directory.appending(path: name).path)[.size] as? Int) ?? 0)
        }
    }

    @Test func foldersAreNamedByTheRecordingsIdentity() throws {
        let (id, directory) = try store.create()

        #expect(directory == store.folder(for: id))
        #expect(directory.lastPathComponent == id.uuidString)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func theListIsNewestFirstWithDateDurationAndSize() async throws {
        let older = try make(created: 1_000, fileBytes: 5_000, durations: [3, 4])
        let newer = try make(created: 2_000, fileBytes: 9_000, durations: [10])

        let list = await store.list()

        #expect(list.map(\.id) == [newer.id, older.id])
        #expect(list[0].createdAt == Date(timeIntervalSince1970: 2_000) && list[0].duration == 10)
        #expect(list[1].duration == 7)
        #expect(list[0].bytes == bytes(of: newer) && list[0].bytes > 9_000)
        #expect(list[1].bytes == bytes(of: older))
        #expect(list.allSatisfy { !$0.isIncomplete })
    }

    @Test func anEmptyOrMissingRecordingsFolderIsAnEmptyList() async {
        #expect(await store.list().isEmpty)
    }

    @Test func foldersThatAreNotRecordingsAreSkippedAndLeftAlone() async throws {
        let real = try make(created: 1)
        try FileManager.default.createDirectory(at: store.root.appending(path: "not-a-recording"), withIntermediateDirectories: true)
        let empty = store.root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let list = await store.list()

        #expect(list.map(\.id) == [real.id])
        #expect(FileManager.default.fileExists(atPath: empty.path))
    }

    @Test func aRecordingStillMarkedAsRecordingIsRescuedAndShownAsIncomplete() async throws {
        let cut = try make(created: 1_000, status: .recording, fileBytes: 2_000, durations: [])

        let list = await store.list()

        // The file is not a movie, so nothing could be rescued; the folder stays and says so.
        #expect(list.count == 1 && list[0].id == cut.id && list[0].isIncomplete && list[0].duration == 0)
        #expect(try RecordingProject.load(from: store.folder(for: cut.id)).status == .interrupted)
        #expect(FileManager.default.fileExists(atPath: store.folder(for: cut.id).appending(path: "segment-001.mov").path))
    }

    @Test func theRecordingBeingMadeNowIsNotRescued() async throws {
        let live = try make(created: 1_000, status: .recording, durations: [])

        let list = await store.list(excluding: [live.id])

        #expect(list.count == 1 && !list[0].isIncomplete)
        #expect(try RecordingProject.load(from: store.folder(for: live.id)).status == .recording)
    }

    @Test func aFinishedRecordingIsNeverTouchedByTheList() async throws {
        let done = try make(created: 1_000)
        let file = store.folder(for: done.id).appending(path: "project.json")
        let before = try Data(contentsOf: file)

        _ = await store.list()

        #expect(try Data(contentsOf: file) == before)
    }

    @Test func discardingRemovesOnlyThatRecordingsFolder() throws {
        let keep = try make(created: 1)
        let drop = try make(created: 2)

        store.discard(id: drop.id)

        #expect(!FileManager.default.fileExists(atPath: store.folder(for: drop.id).path))
        #expect(FileManager.default.fileExists(atPath: store.folder(for: keep.id).path))
        #expect(FileManager.default.fileExists(atPath: store.root.path))
    }
}
