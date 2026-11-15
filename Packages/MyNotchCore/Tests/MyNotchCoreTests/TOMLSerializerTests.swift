import Foundation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct TOMLSerializerTests {
    @Test func roundTripsScalarsAndArrays() throws {
        let initial: TOMLTable = [
            "title": .string("MyNotch Document"),
            "count": .integer(100),
            "ratio": .float(185.0),
            "enabled": .boolean(true),
            "tags": .array([.string("swift"), .string("macos")]),
            "matrix": .array([.integer(1), .integer(2), .integer(3)])
        ]

        let serialized = TOMLSerializer.serialize(initial)
        let reparsed = try TOMLParser.parse(serialized)

        #expect(reparsed["title"] == .string("MyNotch Document"))
        #expect(reparsed["count"] == .integer(100))
        #expect(reparsed["ratio"] == .float(185.0))
        #expect(reparsed["enabled"] == .boolean(true))
        #expect(reparsed["tags"] == .array([.string("swift"), .string("macos")]))
        #expect(reparsed["matrix"] == .array([.integer(1), .integer(2), .integer(3)]))
    }

    @Test func preservesFloatFormatWithPointZero() throws {
        let table: TOMLTable = ["rate": .float(50.0)]
        let text = TOMLSerializer.serialize(table)
        #expect(text.contains("rate = 50.0"))
        let parsed = try TOMLParser.parse(text)
        #expect(parsed["rate"] == .float(50.0))
    }

    @Test func escapesSpecialCharactersAndQuotes() throws {
        let table: TOMLTable = [
            "multiline": .string("Hello\r\nWorld\t\"Quoted\"\\Backslash\u{007F}"),
            "quoted.key-name": .string("Value with dotted key")
        ]
        let serialized = TOMLSerializer.serialize(table)
        #expect(serialized.contains("\\u007F"))
        let parsed = try TOMLParser.parse(serialized)

        #expect(parsed["multiline"] == .string("Hello\r\nWorld\t\"Quoted\"\\Backslash\u{007F}"))
        #expect(parsed["quoted.key-name"] == .string("Value with dotted key"))
    }

    @Test func roundTripsNestedTables() throws {
        let initial: TOMLTable = [
            "app": .table([
                "playSounds": .boolean(false),
                "menuBarHider": .table([
                    "autoHideDelaySeconds": .integer(10)
                ])
            ]),
            "interface": .table([
                "openDelayMs": .integer(120)
            ])
        ]

        let serialized = TOMLSerializer.serialize(initial)
        let reparsed = try TOMLParser.parse(serialized)

        #expect(reparsed == initial)
    }
}
