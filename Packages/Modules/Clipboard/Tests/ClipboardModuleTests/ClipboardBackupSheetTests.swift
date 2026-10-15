import Foundation
import Testing
@testable import ClipboardModule

/// The words of the two sheets, which carry what the user decides by. The windows themselves are checked by eye.
@Suite struct ClipboardBackupSheetTests {
    // MARK: The plan of a restore

    @Test func theOverviewTellsWhatIsNewWhatIsSkippedAndWhatIsMade() {
        let summary = ClipboardRestorePlanSummary(added: 312, duplicates: 18, unreadable: 2, boardsToCreate: 3)
        #expect(ClipboardRestorePlanSheet.overview(summary) == "Tệp có 312 mục mới, 18 mục trùng lặp sẽ bị bỏ qua, 2 mục không đọc được, 3 board mới sẽ được tạo.")
        #expect(ClipboardRestorePlanSheet.overview(ClipboardRestorePlanSummary(added: 5)) == "Tệp có 5 mục mới.")
    }

    @Test func theConsequencesNameTheItemsThatWouldGoAndTheImagesAmongThem() {
        let summary = ClipboardRestorePlanSummary(added: 10, outsideLimits: 4, evictedExisting: 6, evictedExistingImages: 2)
        let lines = ClipboardRestorePlanSheet.consequences(summary)
        #expect(lines == [
            "4 mục vừa khôi phục sẽ bị dọn ngay, vì quá cũ hoặc vượt giới hạn.",
            "6 mục đang có sẽ bị xoá để lấy chỗ, trong đó 2 ảnh (tệp ảnh cũng bị xoá).",
        ])
    }

    @Test func aLineIsLeftOutWhenItsCountIsNone() {
        #expect(ClipboardRestorePlanSheet.consequences(ClipboardRestorePlanSummary(added: 3, outsideLimits: 3)).count == 1)
        let evicted = ClipboardRestorePlanSheet.consequences(ClipboardRestorePlanSummary(added: 3, evictedExisting: 1))
        #expect(evicted == ["1 mục đang có sẽ bị xoá để lấy chỗ."])
        #expect(ClipboardRestorePlanSheet.consequences(ClipboardRestorePlanSummary(added: 3)).isEmpty)
    }

    // MARK: The backup

    @Test func theTickedBoxIsNeverPresentedAsAPromise() {
        let caption = ClipboardBackupOptionsSheet.skipCaption
        #expect(caption.contains("Chỉ những mục mà app đánh dấu"))
        #expect(caption.contains("vẫn nằm trong tệp"))
    }

    @Test func theWarningForOldTextsSaysHowManyAndThatTheyAreInTheFile() {
        let warning = ClipboardBackupOptionsSheet.legacyWarning(120)
        #expect(warning.hasPrefix("120 mục văn bản được lưu trước khi"))
        #expect(warning.contains("vẫn nằm trong tệp, kể cả khi đã bỏ qua mục nhạy cảm"))
        #expect(warning.contains("Mật khẩu có thể nằm trong số đó"))
    }
}
