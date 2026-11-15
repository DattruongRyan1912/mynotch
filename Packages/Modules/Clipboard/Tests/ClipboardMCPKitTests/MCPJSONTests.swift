import Foundation
import Testing
@testable import ClipboardMCPKit

@Suite struct MCPJSONTests {
    private func decode(_ text: String) throws -> JSON {
        try JSON(decoding: Data(text.utf8))
    }

    @Test func readsEveryKindOfValue() throws {
        let value = try decode(#"{"a":null,"b":true,"c":3,"d":1.5,"e":"x","f":[1,"y"],"g":{"h":false}}"#)
        #expect(value == .object([
            "a": .null, "b": .bool(true), "c": .int(3), "d": .double(1.5), "e": .string("x"),
            "f": .array([.int(1), .string("y")]), "g": .object(["h": .bool(false)]),
        ]))
    }

    @Test func aNumberThatIsNotAnIntegerStaysADouble() throws {
        #expect(try decode("2.5") == .double(2.5))
        #expect(try decode("7") == .int(7))
        #expect(try decode("true") == .bool(true))
    }

    @Test func invalidTextThrows() {
        for text in ["", "{", "{\"a\":}", "[1 2]", "nope", "{'a':1}", "{\"a\":1} x"] {
            #expect(throws: (any Error).self) { try JSON(decoding: Data(text.utf8)) }
        }
    }

    @Test func veryDeepNestingIsRefusedInsteadOfCrashing() {
        let text = String(repeating: "[", count: 20_000) + String(repeating: "]", count: 20_000)
        #expect(throws: (any Error).self) { try JSON(decoding: Data(text.utf8)) }
    }

    @Test func writesCompactTextWithSortedKeysAndPlainSlashes() throws {
        let value = JSON.object(["b": .int(1), "a": .string("x/y"), "c": .array([.null, .bool(false)])])
        #expect(String(decoding: try value.encoded(), as: UTF8.self) == #"{"a":"x/y","b":1,"c":[null,false]}"#)
    }

    @Test func aLineNeverHoldsANewlineOrALineSeparator() throws {
        // The transport splits on newlines, and some readers also split on U+2028 and U+2029.
        let value = JSON.object(["text": .string("one\ntwo\r\nthree\u{2028}four\u{2029}five")])
        let bytes = try value.encoded()
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("\n"))
        #expect(!text.contains("\r"))
        #expect(!text.contains("\u{2028}"))
        #expect(!text.contains("\u{2029}"))
        #expect(try JSON(decoding: bytes) == value)
    }

    @Test func accessorsAnswerOnlyForTheirOwnKind() {
        let value = JSON.object(["s": .string("x"), "i": .int(2), "o": .object([:]), "d": .double(4)])
        #expect(value["s"]?.string == "x")
        #expect(value["s"]?.int == nil)
        #expect(value["i"]?.int == 2)
        #expect(value["o"]?.object == [:])
        #expect(value["d"]?.int == 4)
        #expect(JSON.double(4.5).int == nil)
        #expect(JSON.string("x")["a"] == nil)
        #expect(value["missing"] == nil)
    }
}
