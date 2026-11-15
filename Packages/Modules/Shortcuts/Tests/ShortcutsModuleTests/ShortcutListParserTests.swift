import Testing
@testable import ShortcutsModule

@Suite struct ShortcutListParserTests {
    @Test func readsNamesAndIdentifiers() {
        let output = """
        Morning Routine (0F1A2B3C-4D5E-6F70-8192-A3B4C5D6E7F8)
        Resize Image (11111111-2222-3333-4444-555555555555)

        """
        #expect(ShortcutListParser.parse(output) == [
            ShortcutInfo(id: "0F1A2B3C-4D5E-6F70-8192-A3B4C5D6E7F8", name: "Morning Routine"),
            ShortcutInfo(id: "11111111-2222-3333-4444-555555555555", name: "Resize Image"),
        ])
    }

    @Test func keepsParenthesesInTheName() {
        let output = "Backup (daily) (v2) (0F1A2B3C-4D5E-6F70-8192-A3B4C5D6E7F8)"
        #expect(ShortcutListParser.parse(output).map(\.name) == ["Backup (daily) (v2)"])
    }

    @Test func keepsUnicodeNames() {
        let output = "Mở nhạc 🎵 (11111111-2222-3333-4444-555555555555)\n日本語 (22222222-3333-4444-5555-666666666666)"
        #expect(ShortcutListParser.parse(output).map(\.name) == ["Mở nhạc 🎵", "日本語"])
    }

    @Test func skipsLinesWithoutAnIdentifier() {
        let output = """
        Warning: something
        No id here (not-a-uuid)
         (11111111-2222-3333-4444-555555555555)
        Fine (11111111-2222-3333-4444-555555555555)
        """
        #expect(ShortcutListParser.parse(output).map(\.name) == ["Fine"])
    }

    @Test func toleratesWindowsLineEndingsAndPadding() {
        let output = "  Padded   (11111111-2222-3333-4444-555555555555)  \r\nOther (22222222-3333-4444-5555-666666666666)\r\n"
        #expect(ShortcutListParser.parse(output).map(\.name) == ["Padded", "Other"])
    }

    @Test func dropsDuplicateIdentifiers() {
        let output = "A (11111111-2222-3333-4444-555555555555)\nB (11111111-2222-3333-4444-555555555555)"
        #expect(ShortcutListParser.parse(output).map(\.name) == ["A"])
    }

    @Test func emptyOutputHasNoShortcuts() {
        #expect(ShortcutListParser.parse("").isEmpty)
    }
}
