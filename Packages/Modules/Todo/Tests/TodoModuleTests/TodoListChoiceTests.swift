import Testing
@testable import TodoModule

@Suite struct TodoListChoiceTests {
    func list(_ id: String, _ title: String? = nil, writable: Bool = true, isDefault: Bool = false) -> TodoListInfo {
        TodoListInfo(id: id, title: title ?? id, color: .gray, allowsModifications: writable, isDefaultForNewReminders: isDefault)
    }

    @Test func theChosenListWins() {
        let lists = [list("a", isDefault: true), list("b")]
        #expect(TodoListChoice.resolve(chosenID: "b", in: lists)?.id == "b")
    }

    @Test func aListThatIsGoneFallsBackToTheSystemsOne() {
        let lists = [list("a"), list("b", isDefault: true)]
        #expect(TodoListChoice.resolve(chosenID: "gone", in: lists)?.id == "b")
        #expect(TodoListChoice.resolve(chosenID: nil, in: lists)?.id == "b")
    }

    @Test func aReadOnlyListIsNeverChosenNorDefault() {
        let lists = [list("subscribed", writable: false, isDefault: true), list("mine")]
        #expect(TodoListChoice.resolve(chosenID: "subscribed", in: lists)?.id == "mine")
    }

    @Test func withoutADefaultTheFirstByTitleTakesIt() {
        let lists = [list("2", "Work"), list("1", "Home")]
        #expect(TodoListChoice.resolve(chosenID: nil, in: lists)?.id == "1")
    }

    @Test func noListThatTakesRemindersMeansNoChoice() {
        #expect(TodoListChoice.resolve(chosenID: nil, in: []) == nil)
        #expect(TodoListChoice.resolve(chosenID: nil, in: [list("a", writable: false)]) == nil)
    }

    @Test func listsSortByTitleThenId() {
        let sorted = TodoListChoice.sorted([list("3", "Work"), list("2", "Work"), list("1", "Home")])
        #expect(sorted.map(\.id) == ["1", "2", "3"])
    }

    @Test func hidingAndShowingAList() {
        #expect(TodoListChoice.isVisible("a", hidden: []))
        #expect(!TodoListChoice.isVisible("a", hidden: ["a"]))
        #expect(TodoListChoice.setting("a", visible: false, in: []) == ["a"])
        #expect(TodoListChoice.setting("a", visible: false, in: ["a"]) == ["a"])
        #expect(TodoListChoice.setting("a", visible: true, in: ["a", "b"]) == ["b"])
        #expect(TodoListChoice.setting("a", visible: true, in: ["b"]) == ["b"])
    }
}
