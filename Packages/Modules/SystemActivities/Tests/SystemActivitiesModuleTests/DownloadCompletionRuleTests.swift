import Foundation
import Testing
@testable import SystemActivitiesModule

@Suite struct DownloadCompletionRuleTests {
    static let dir = "/Users/me/Downloads/"
    let start = Date(timeIntervalSince1970: 1_000)
    var rule = DownloadCompletionRule()

    func observe(
        _ name: String, _ flags: FileObservation.Flags, size: Int64 = 0, origin: Bool = false, directory: Bool = false,
        date: Date? = nil
    ) -> FileObservation {
        FileObservation(
            path: Self.dir + name, flags: flags, size: size, hasOrigin: origin, isDirectory: directory, date: date ?? start)
    }

    mutating func feed(_ observation: FileObservation, at seconds: Double) {
        rule.observe(observation, now: start.addingTimeInterval(seconds))
    }

    mutating func tick(at seconds: Double) -> [DownloadEvent] {
        rule.tick(now: start.addingTimeInterval(seconds))
    }

    static func event(_ name: String) -> DownloadEvent {
        DownloadEvent(url: URL(fileURLWithPath: dir + name), name: name)
    }

    @Test mutating func safariBundleDisappearsAndTheFinalFileSettles() {
        feed(observe("report.pdf.download", .created, directory: true), at: 0)
        feed(observe("report.pdf.download", .modified, directory: true), at: 1)
        #expect(tick(at: 5).isEmpty)
        feed(observe("report.pdf.download", .removed, directory: true), at: 6)
        feed(observe("report.pdf", .created, size: 2_000, origin: true), at: 6)
        #expect(tick(at: 6.5).isEmpty)
        #expect(tick(at: 7.1) == [Self.event("report.pdf")])
        #expect(tick(at: 9).isEmpty)
    }

    @Test mutating func chromeRenamesTheCrdownloadFile() {
        feed(observe("a.zip.crdownload", .created, size: 10), at: 0)
        feed(observe("a.zip.crdownload", .modified, size: 5_000), at: 2)
        feed(observe("a.zip.crdownload", [.renamed, .removed]), at: 3)
        feed(observe("a.zip", .renamed, size: 5_000), at: 3)
        #expect(tick(at: 3.5).isEmpty)
        #expect(tick(at: 4.1) == [Self.event("a.zip")])
    }

    @Test mutating func firefoxPlaceholderAndPartFile() {
        feed(observe("b.iso", .created, size: 0), at: 0)
        feed(observe("b.iso.part", .created, size: 100), at: 0)
        feed(observe("b.iso.part", .modified, size: 9_000), at: 2)
        #expect(tick(at: 10).isEmpty)
        feed(observe("b.iso.part", .removed), at: 11)
        feed(observe("b.iso", .renamed, size: 9_000), at: 11)
        #expect(tick(at: 11.5).isEmpty)
        #expect(tick(at: 12.1) == [Self.event("b.iso")])
    }

    @Test mutating func aZeroByteFileIsNotComplete() {
        feed(observe("c.pdf.crdownload", .created), at: 0)
        feed(observe("c.pdf.crdownload", .removed), at: 1)
        feed(observe("c.pdf", .created, size: 0), at: 1)
        #expect(tick(at: 5).isEmpty)
    }

    @Test mutating func aGrowingFileWaitsUntilItsSizeIsStable() {
        feed(observe("d.mov.crdownload", .removed), at: 0)
        feed(observe("d.mov", .created, size: 100, origin: true), at: 0)
        feed(observe("d.mov", .modified, size: 200, origin: true), at: 0.8)
        #expect(tick(at: 1.2).isEmpty)
        feed(observe("d.mov", .modified, size: 300, origin: true), at: 1.6)
        #expect(tick(at: 2.5).isEmpty)
        #expect(tick(at: 2.7) == [Self.event("d.mov")])
    }

    @Test mutating func aFinalFileWithOriginAndNoPartialMarkerCompletes() {
        feed(observe("e.dmg", .created, size: 500, origin: true), at: 0)
        #expect(tick(at: 1.1) == [Self.event("e.dmg")])
    }

    @Test mutating func aPlainCopyWithoutOriginIsNotADownload() {
        feed(observe("copy.txt", .created, size: 500), at: 0)
        feed(observe("copy.txt", .modified, size: 600), at: 0.5)
        #expect(tick(at: 10).isEmpty)
    }

    @Test mutating func dotfilesAndOtherDirectoriesAreIgnored() {
        feed(observe(".DS_Store", .created, size: 500, origin: true), at: 0)
        feed(observe(".hidden.crdownload", .created, size: 5), at: 0)
        feed(observe(".hidden", .created, size: 500, origin: true), at: 0)
        feed(observe("folder", .created, size: 64, origin: true, directory: true), at: 0)
        #expect(tick(at: 10).isEmpty)
    }

    @Test mutating func aRemovedFileIsForgotten() {
        feed(observe("f.pdf", .created, size: 500, origin: true), at: 0)
        feed(observe("f.pdf", .removed), at: 0.5)
        #expect(tick(at: 10).isEmpty)
    }

    @Test mutating func aResumedDownloadIsNotCompleteUntilItFinishesAgain() {
        feed(observe("g.zip", .created, size: 500, origin: true), at: 0)
        feed(observe("g.zip.crdownload", .created, size: 500), at: 0.5)
        #expect(tick(at: 10).isEmpty)
        feed(observe("g.zip.crdownload", .removed), at: 11)
        feed(observe("g.zip", .renamed, size: 900), at: 11)
        #expect(tick(at: 12.1) == [Self.event("g.zip")])
    }

    @Test mutating func laterTouchesOfACompletedFileDoNotRepeatTheEvent() {
        feed(observe("h.pdf", .created, size: 500, origin: true), at: 0)
        #expect(tick(at: 1.1).count == 1)
        feed(observe("h.pdf", .modified, size: 500, origin: true), at: 5)
        #expect(tick(at: 9).isEmpty)
    }

    @Test mutating func burstsOfObservationsAreDebounced() {
        feed(observe("i.pdf", .created, size: 500, origin: true), at: 0)
        feed(observe("i.pdf", .modified, size: 500, origin: true), at: 0.9)
        #expect(tick(at: 1.1).isEmpty)
        #expect(tick(at: 1.25) == [Self.event("i.pdf")])
    }

    @Test mutating func hasPendingReflectsWaitingCandidates() {
        #expect(!rule.hasPending)
        feed(observe("j.pdf", .created, size: 500, origin: true), at: 0)
        #expect(rule.hasPending)
        _ = tick(at: 2)
        #expect(!rule.hasPending)
    }

    @Test mutating func anOldQuarantinedFileTouchedLaterIsNotADownload() {
        let old = start.addingTimeInterval(-86_400)
        feed(observe("old.dmg", .modified, size: 500, origin: true, date: old), at: 0)
        #expect(tick(at: 5).isEmpty)
        #expect(!rule.hasPending)
    }

    @Test mutating func anOriginOnlyFileMustBeFreshToStartACandidate() {
        feed(observe("fresh.dmg", .created, size: 500, origin: true, date: start.addingTimeInterval(-9)), at: 0)
        feed(observe("stale.dmg", .created, size: 500, origin: true, date: start.addingTimeInterval(-11)), at: 0)
        #expect(tick(at: 1.1) == [Self.event("fresh.dmg")])
    }

    @Test mutating func aFileWithAPartialMarkerIgnoresItsDate() {
        let old = start.addingTimeInterval(-3_600)
        feed(observe("long.zip.crdownload", .created, size: 10), at: 0)
        feed(observe("long.zip.crdownload", .removed), at: 1)
        feed(observe("long.zip", .renamed, size: 900, origin: true, date: old), at: 1)
        #expect(tick(at: 2.1) == [Self.event("long.zip")])
    }

    @Test mutating func aCandidateThatNeverCompletesExpiresAfterTenMinutes() {
        feed(observe("empty.pdf", .created, size: 0, origin: true), at: 0)
        #expect(tick(at: 599).isEmpty)
        #expect(rule.hasPending)
        #expect(tick(at: 600).isEmpty)
        #expect(!rule.hasPending)
    }

    @Test mutating func aCompletedFileIsForgottenAfterAnHour() {
        feed(observe("k.pdf", .created, size: 500, origin: true), at: 0)
        #expect(tick(at: 1.1).count == 1)
        let later = start.addingTimeInterval(4_000)
        feed(observe("k.pdf", .created, size: 500, origin: true, date: later), at: 4_000)
        #expect(tick(at: 4_001.1) == [Self.event("k.pdf")])
    }

    @Test mutating func aForgottenPartialMarkerNoLongerMakesTheFinalFileACandidate() {
        feed(observe("m.zip.crdownload", .created, size: 10), at: 0)
        feed(observe("m.zip.crdownload", .removed), at: 1)
        _ = tick(at: 4_000)
        feed(observe("m.zip", .created, size: 900), at: 4_001)
        #expect(tick(at: 4_010).isEmpty)
    }
}
