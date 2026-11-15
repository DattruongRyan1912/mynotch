import Foundation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct TOMLParserTests {
    @Test func parsesBasicAndLiteralStrings() throws {
        let input = """
        str = "Hello, World!"
        escaped = "Line 1\\nLine 2\\tTabbed \\"Quotes\\""
        literal = 'C:\\Users\\Desktop\\file.txt'
        unicode = "Heart: \\u2764"
        """
        let table = try TOMLParser.parse(input)
        #expect(table["str"] == .string("Hello, World!"))
        #expect(table["escaped"] == .string("Line 1\nLine 2\tTabbed \"Quotes\""))
        #expect(table["literal"] == .string("C:\\Users\\Desktop\\file.txt"))
        #expect(table["unicode"] == .string("Heart: \u{2764}"))
    }

    @Test func parsesMultilineStrings() throws {
        let input = """
        multiBasic = \"\"\"
        The quick brown \
        fox jumps over \
        the lazy dog.\"\"\"
        multiLiteral = '''
        First line
        Second line with \\no escape
        '''
        """
        let table = try TOMLParser.parse(input)
        #expect(table["multiBasic"] == .string("The quick brown fox jumps over the lazy dog."))
        #expect(table["multiLiteral"] == .string("First line\nSecond line with \\no escape\n"))
    }

    @Test func parsesCRLFLineEndings() throws {
        let input = "name = \"MyNotch\"\r\nversion = 2\r\nenabled = true\r\n"
        let table = try TOMLParser.parse(input)
        #expect(table["name"] == .string("MyNotch"))
        #expect(table["version"] == .integer(2))
        #expect(table["enabled"] == .boolean(true))
    }

    @Test func parsesIntegersAndRadix() throws {
        let input = """
        dec1 = 42
        dec2 = +99
        dec3 = -17
        decUnderscore = 1_000_000
        hex = 0xDEADBEEF
        oct = 0o755
        bin = 0b1101
        """
        let table = try TOMLParser.parse(input)
        #expect(table["dec1"] == .integer(42))
        #expect(table["dec2"] == .integer(99))
        #expect(table["dec3"] == .integer(-17))
        #expect(table["decUnderscore"] == .integer(1000000))
        #expect(table["hex"] == .integer(0xDEADBEEF))
        #expect(table["oct"] == .integer(0o755))
        #expect(table["bin"] == .integer(0b1101))
    }

    @Test func parsesFloatsAndSpecials() throws {
        let input = """
        flt1 = 3.14159
        flt2 = -0.01
        flt3 = 5e+22
        flt4 = 1e6
        flt5 = -2E-2
        infPos = inf
        infNeg = -inf
        nanVal = nan
        """
        let table = try TOMLParser.parse(input)
        #expect(table["flt1"] == .float(3.14159))
        #expect(table["flt2"] == .float(-0.01))
        #expect(table["flt3"] == .float(5e22))
        #expect(table["flt4"] == .float(1e6))
        #expect(table["flt5"] == .float(-0.02))
        #expect(table["infPos"] == .float(.infinity))
        #expect(table["infNeg"] == .float(-.infinity))
        #expect(table["nanVal"] == .float(.nan))
    }

    @Test func parsesBooleans() throws {
        let input = """
        boolTrue = true
        boolFalse = false
        """
        let table = try TOMLParser.parse(input)
        #expect(table["boolTrue"] == .boolean(true))
        #expect(table["boolFalse"] == .boolean(false))
    }

    @Test func parsesArraysWithCommentsAndTrailingCommas() throws {
        let input = """
        arr = [
            1,
            2, # comment inside array
            3,
        ]
        nested = [[1, 2], [3, 4]]
        empty = []
        """
        let table = try TOMLParser.parse(input)
        #expect(table["arr"] == .array([.integer(1), .integer(2), .integer(3)]))
        #expect(table["nested"] == .array([
            .array([.integer(1), .integer(2)]),
            .array([.integer(3), .integer(4)])
        ]))
        #expect(table["empty"] == .array([]))
    }

    @Test func parsesInlineTablesAndDottedKeys() throws {
        let input = """
        point = { x = 10, y = 20 }
        nested = { a.b.c = "deep", active = true }
        """
        let table = try TOMLParser.parse(input)
        #expect(table["point"] == .table(["x": .integer(10), "y": .integer(20)]))
        #expect(table["nested"] == .table([
            "a": .table(["b": .table(["c": .string("deep")])]),
            "active": .boolean(true)
        ]))
    }

    @Test func parsesSectionsAndHierarchy() throws {
        let input = """
        title = "Root Title"

        [app]
        playSounds = true

        [app.menuBarHider]
        autoHideDelaySeconds = 5

        [interface]
        openDelayMs = 150
        """
        let table = try TOMLParser.parse(input)
        #expect(table["title"] == .string("Root Title"))
        guard case .table(let app) = table["app"] else {
            Issue.record("Missing [app] table")
            return
        }
        #expect(app["playSounds"] == .boolean(true))
        guard case .table(let hider) = app["menuBarHider"] else {
            Issue.record("Missing [app.menuBarHider] table")
            return
        }
        #expect(hider["autoHideDelaySeconds"] == .integer(5))
    }

    @Test func parsesRepeatedArrayOfTablesWithSubSections() throws {
        let input = """
        [[items]]
        name = "first"
        [items.meta]
        priority = 1

        [[items]]
        name = "second"
        [items.meta]
        priority = 2
        """
        let table = try TOMLParser.parse(input)
        guard case .array(let arr) = table["items"] else {
            Issue.record("Expected [[items]] array")
            return
        }
        #expect(arr.count == 2)
        if case .table(let item1) = arr[0] {
            #expect(item1["name"] == .string("first"))
            if case .table(let meta1) = item1["meta"] {
                #expect(meta1["priority"] == .integer(1))
            }
        }
        if case .table(let item2) = arr[1] {
            #expect(item2["name"] == .string("second"))
            if case .table(let meta2) = item2["meta"] {
                #expect(meta2["priority"] == .integer(2))
            }
        }
    }

    @Test func parsesToDictionary() throws {
        let input = """
        [interface]
        openDelayMs = 150
        tags = ["a", "b"]
        """
        let dict = try TOMLParser.parseToDictionary(input)
        guard let iface = dict["interface"] as? [String: Any] else {
            Issue.record("Missing interface dictionary")
            return
        }
        #expect(iface["openDelayMs"] as? Int == 150)
        #expect(iface["tags"] as? [String] == ["a", "b"])
    }

    @Test func throwsAccurateErrorsForInvalidSyntax() {
        // Unexpected char
        #expect(throws: TOMLError.self) {
            _ = try TOMLParser.parse("foo = @invalid")
        }

        // Unterminated string
        #expect(throws: TOMLError.self) {
            _ = try TOMLParser.parse("foo = \"unclosed string")
        }

        // Duplicate key
        #expect(throws: TOMLError.self) {
            _ = try TOMLParser.parse("a = 1\na = 2")
        }

        // Expected equals
        #expect(throws: TOMLError.self) {
            _ = try TOMLParser.parse("key_without_equals 42")
        }

        // Invalid numbers (leading zeros in decimal, invalid underscores)
        #expect(throws: TOMLError.self) { _ = try TOMLParser.parse("num = 0123") }
        #expect(throws: TOMLError.self) { _ = try TOMLParser.parse("num = 1__000") }
        #expect(throws: TOMLError.self) { _ = try TOMLParser.parse("num = 100_") }
        #expect(throws: TOMLError.self) { _ = try TOMLParser.parse("num = _100") }
    }

    @Test func mapsDirectlyToSettingKey() throws {
        let input = """
        [interface]
        openDelayMs = 250
        clampedDelay = 5000
        tags = ["fast", "compact"]
        """
        let table = try TOMLParser.parse(input)
        let key = SettingKey("interface.openDelayMs", default: 150)
        let clampedKey = SettingKey("interface.clampedDelay", default: 300, clampedTo: 0...1000)
        let tagsKey = SettingKey<[String]>("interface.tags", default: [])

        #expect(table.settingValue(for: key) == 250)
        #expect(table.settingValue(for: clampedKey) == 1000)
        #expect(table.settingValue(for: tagsKey) == ["fast", "compact"])
    }
}
