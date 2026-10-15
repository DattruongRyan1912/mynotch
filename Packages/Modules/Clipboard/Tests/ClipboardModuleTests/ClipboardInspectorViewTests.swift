import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The inspector pane, the compact previews it uses and the editor's content, built and measured in memory (no window, no screen).
/// How they look is for the person to check; here, that each state is built and fits where it is shown.
@Suite struct ClipboardInspectorViewTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    final class Fixture {
        let module: ClipboardModule
        let state = ClipboardState()
        let actions: FakeLibraryActions
        let model: ClipboardLibraryModel
        let ids: [String: UUID]

        init() {
            // A module that is not running: it only has to exist for the views to be given one.
            module = ClipboardEditorModuleTests().module
            var history = ClipboardHistory()
            var ids: [String: UUID] = [:]
            func add(_ name: String, _ content: ClipboardContent) {
                ids[name] = history.add(content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Notes", "Ghi chú"), at: ClipboardInspectorViewTests.start).id
            }
            add("text", .text("Xin chào thế giới\nHôm nay trời đẹp quá, chúng ta cùng đi dạo quanh hồ nhé."))
            add("code", .text("func add(_ a: Int, _ b: Int) -> Int {\n    return a + b\n}\n"))
            add("link", .link(URL(string: "https://example.com/a/b?c=1")!))
            add("color", .color(hex: "#FF8800"))
            add("image", .image(ClipboardImage(fileName: "a.png", pixelWidth: 1920, pixelHeight: 1080, byteCount: 2_000_000)))
            add("files", .files([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]))
            add("long", .text(String(repeating: "Xin chào thế giới\n", count: 6_000)))
            let board = history.createBoard(name: "Két")
            history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 4, isUnlocked: false)
            _ = board
            state.history = history
            self.ids = ids
            actions = FakeLibraryActions(state: state)
            model = ClipboardLibraryModel(state: state, actions: actions)
        }

        var pane: some View {
            ClipboardInspectorView(module: module, model: model, requestName: { _ in })
                .environment(\.notchAccent, .cyan)
        }
    }

    func size(of view: some View) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    // MARK: The pane

    @Test(arguments: ["text", "code", "link", "color", "image", "files", "long"])
    func everyKindIsBuiltAtThePanesWidth(name: String) throws {
        let fixture = Fixture()
        fixture.model.select(try #require(fixture.ids[name]), mode: .replace)
        guard case .item = fixture.model.inspector else {
            Issue.record("Expected the item's fields for \(name)")
            return
        }
        let size = size(of: fixture.pane)
        #expect(size.width == ClipboardInspectorView.width, "\(name) is \(size.width) wide")
        #expect(size.height > 0)
    }

    @Test func nothingFocusedAndALockedBoardAreBuiltToo() throws {
        let fixture = Fixture()
        #expect(fixture.model.inspector == .nothing)
        #expect(size(of: fixture.pane).width == ClipboardInspectorView.width)

        fixture.model.selection = .board(fixture.state.history.boards[0].id)
        #expect(fixture.model.inspector == .locked)
        #expect(size(of: fixture.pane).width == ClipboardInspectorView.width)
    }

    @Test func theInspectorFitsBesideTheCardsInTheSmallestLibraryWindow() {
        // The window is 760 pt at least, with a sidebar of 190 pt at least: the cards keep a column of their own.
        #expect(760 - 190 - ClipboardInspectorView.width >= 240)
    }

    @Test func aTextThatLooksLikeAnotherItemsIsADifferentPreview() {
        let first = ClipboardPreviewIdentity(id: UUID(), contentHash: "a")
        #expect(first == ClipboardPreviewIdentity(id: first.id, contentHash: "a"))
        // An item the editor replaced keeps its id and takes a new hash: its preview is drawn again.
        #expect(first != ClipboardPreviewIdentity(id: first.id, contentHash: "b"))
    }

    // MARK: The compact previews

    @Test func theCompactTextIsSmallerThanTheLargeOne() {
        func fontSize(isCode: Bool, isCompact: Bool) -> CGFloat {
            let attributed = ClipboardPreviewTextView.attributed("abc", isCode: isCode, isCompact: isCompact)
            return (attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        }
        #expect(fontSize(isCode: false, isCompact: true) < fontSize(isCode: false, isCompact: false))
        #expect(fontSize(isCode: true, isCompact: true) < fontSize(isCode: true, isCompact: false))
        #expect(fontSize(isCode: true, isCompact: false) == ClipboardPreviewTextView.codeSize)
    }

    @Test func everyCompactPaneIsBuiltInTheSpaceOfThePreviewBox() throws {
        let fixture = Fixture()
        let items = fixture.state.history.items
        for item in items {
            let pane = ClipboardPreviewPane(content: ClipboardPreviewContent(item: item, facts: .none), item: item, imageSource: nil, isCompact: true)
                .frame(width: ClipboardInspectorView.width - 28, height: 190)
            #expect(size(of: pane).height <= 190, "\(item.content.kind)")
        }
    }

    // MARK: The editor

    func editorModel(_ content: ClipboardContent = .text("Xin chào")) -> ClipboardEditorModel {
        let item = ClipboardItem(id: UUID(), content: content, contentHash: "h", copiedAt: Self.start, codeDetection: ClipboardCodeDetector.detect(content))
        return ClipboardEditorModel(item: item, text: ClipboardEditing.text(of: item) ?? "", save: { _, _ in .stopped }, close: {})
    }

    @Test func theEditorIsBuiltForEveryStateOfItsFooter() {
        let plain = editorModel()
        #expect(size(of: ClipboardEditorView(model: plain).environment(\.notchAccent, .cyan)).width >= 440)

        let code = editorModel(.text("func add(_ a: Int, _ b: Int) -> Int {\n    // tổng\n    return a + b\n}\n"))
        #expect(code.detectedLanguage == .swift)
        #expect(size(of: ClipboardEditorView(model: code).environment(\.notchAccent, .cyan)).height >= 280)

        let rich = editorModel(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 x}".utf8)))
        let refused = editorModel()
        refused.text = "khác"
        refused.save(.replace)
        #expect(refused.notice != nil)
        for model in [rich, refused] {
            #expect(size(of: ClipboardEditorView(model: model).environment(\.notchAccent, .cyan)).width >= 440)
        }
    }

    @Test func theEditorsTextTakesTheWordsAsTheyAreAndWillNotChangeThem() throws {
        let textView = try #require(NSTextView.scrollableTextView().documentView as? NSTextView)
        ClipboardEditorTextView.configure(textView)
        #expect(textView.isEditable && textView.allowsUndo && textView.usesFindBar)
        #expect(!textView.isRichText)
        // Nothing is rewritten while typing: a straight quote stays straight, two hyphens stay two.
        #expect(!textView.isAutomaticQuoteSubstitutionEnabled)
        #expect(!textView.isAutomaticDashSubstitutionEnabled)
        #expect(!textView.isAutomaticTextReplacementEnabled)
        #expect(!textView.isAutomaticSpellingCorrectionEnabled)
        #expect(!textView.isAutomaticLinkDetectionEnabled)
        #expect(!textView.isAutomaticDataDetectionEnabled)
        #expect(!textView.isContinuousSpellCheckingEnabled)
        // What is typed may be a secret of an open board: nothing completes, predicts or rewrites it.
        #expect(!textView.isAutomaticTextCompletionEnabled)
        #expect(textView.inlinePredictionType == .no)
        #expect(textView.writingToolsBehavior == .none)
    }

    @Test func theMonospacedToggleChoosesAFixedWidthFont() {
        #expect(ClipboardEditorTextView.font(monospaced: true).isFixedPitch)
        #expect(!ClipboardEditorTextView.font(monospaced: false).isFixedPitch)
    }
}
