import Testing
@testable import ClipboardModule

@Suite struct TextTransformTests {
    @Test func everyTransformHasAVietnameseTitleInMenuOrder() {
        #expect(TextTransform.allCases.map(\.title) == [
            "VIẾT HOA", "viết thường", "Viết Hoa Chữ Đầu", "Bỏ khoảng trắng thừa", "Bỏ dòng trống", "Sắp xếp dòng",
            "JSON: định dạng", "JSON: thu gọn", "Base64: mã hoá", "Base64: giải mã", "URL: mã hoá", "URL: giải mã",
        ])
    }

    @Test func caseTransforms() {
        #expect(TextTransform.uppercase.apply("Xin chào thế giới") == "XIN CHÀO THẾ GIỚI")
        #expect(TextTransform.lowercase.apply("ĐỒNG Hồ iPhone") == "đồng hồ iphone")
        #expect(TextTransform.capitalizeWords.apply("đồng hồ THÔNG minh\nhello-world") == "Đồng Hồ Thông Minh\nHello-World")
        // Like macOS's own Capitalize: the rest of each word is lowercased, acronyms and brand casing included.
        #expect(TextTransform.capitalizeWords.apply("iPhone HTTP") == "Iphone Http")
    }

    @Test func trimWhitespaceTrimsTheEndsAndCollapsesRunsAfterTheIndentation() {
        #expect(TextTransform.trimWhitespace.apply("\n  a   b \t c  \n\n\t d\t\te \n ") == "a b c\n\n\t d e")
        #expect(TextTransform.trimWhitespace.apply("one\r\n  two  ") == "one\n  two")
        #expect(TextTransform.trimWhitespace.apply("   ") == "")
    }

    @Test func trimWhitespaceKeepsCodeIndentation() {
        let code = "func f() {\n    let x  =  1   \n  \n    if x  > 0 {\n\t\treturn  x\t\n    }\n}\n"
        #expect(TextTransform.trimWhitespace.apply(code) == "func f() {\n    let x = 1\n\n    if x > 0 {\n\t\treturn x\n    }\n}")
    }

    @Test func trimWhitespaceTreatsNonBreakingSpacesAsSpaces() {
        #expect(TextTransform.trimWhitespace.apply("a\u{00A0}\u{00A0}b\u{00A0}\n\u{00A0}c") == "a b\n\u{00A0}c")
    }

    @Test func removeEmptyLinesKeepsOtherLinesVerbatim() {
        #expect(TextTransform.removeEmptyLines.apply("a\n\n  b \n \t\nc\r\n\r\nd\n") == "a\n  b \nc\nd")
    }

    @Test func sortLinesUsesLocalizedStandardOrder() {
        #expect(TextTransform.sortLines.apply("item10\nitem2\nBánh\nan") == "an\nBánh\nitem2\nitem10")
        // Trailing empty lines stay at the end instead of sorting to the top.
        #expect(TextTransform.sortLines.apply("b\na\n") == "a\nb\n")
        #expect(TextTransform.sortLines.apply("b\na\n\n \n") == "a\nb\n\n \n")
        #expect(TextTransform.sortLines.apply("b\n\na") == "\na\nb")
        #expect(TextTransform.sortLines.apply("\n\n") == "\n\n")
    }

    @Test func jsonPrettyPrintsWithSortedKeysAndUnescapedSlashes() {
        let json = #" {"b": [1, 2.5, true, null], "a": "x/yé", "c": {"z": 1, "y": "Đ"}} "#
        #expect(TextTransform.jsonPretty.apply(json) == """
        {
          "a" : "x/yé",
          "b" : [
            1,
            2.5,
            true,
            null
          ],
          "c" : {
            "y" : "Đ",
            "z" : 1
          }
        }
        """)
    }

    @Test func jsonPrettyKeepsEmptyContainersOnOneLine() {
        #expect(TextTransform.jsonPretty.apply("{ }") == "{}")
        #expect(TextTransform.jsonPretty.apply("[\n]") == "[]")
        // Line breaks inside strings are escaped, so only real empty containers are joined.
        #expect(TextTransform.jsonPretty.apply(#"{"a": {}, "b": [[], {}], "c": "{\n\n}"}"#) == #"""
        {
          "a" : {},
          "b" : [
            [],
            {}
          ],
          "c" : "{\n\n}"
        }
        """#)
    }

    @Test func jsonMinifyRemovesWhitespaceWithSortedKeys() {
        let json = """
        {
          "b" : [ 1, "a b" ],
          "a" : "https://example.com/x"
        }
        """
        #expect(TextTransform.jsonMinify.apply(json) == #"{"a":"https://example.com/x","b":[1,"a b"]}"#)
        #expect(TextTransform.jsonMinify.apply("[ ]") == "[]")
    }

    @Test func jsonTransformsKeepNumbersExactly() {
        let json = #"{"id": 12345678901234567890, "price": 19.99, "ratio": 0.1, "list": [0.1, -2.5, 0]}"#
        #expect(TextTransform.jsonMinify.apply(json) == #"{"id":12345678901234567890,"list":[0.1,-2.5,0],"price":19.99,"ratio":0.1}"#)
        #expect(TextTransform.jsonPretty.apply(json) == """
        {
          "id" : 12345678901234567890,
          "list" : [
            0.1,
            -2.5,
            0
          ],
          "price" : 19.99,
          "ratio" : 0.1
        }
        """)
    }

    @Test(arguments: [TextTransform.jsonPretty, .jsonMinify], [
        "", "hello", "{\"a\": }", "{'a': 1}", "[1, 2", "123", "\"text\"", "true", "null", "[1e400]",
    ])
    func invalidJSONIsNotApplicable(transform: TextTransform, input: String) {
        #expect(transform.apply(input) == nil)
    }

    @Test func base64RoundTripsUTF8() {
        #expect(TextTransform.base64Encode.apply("Xin chào") == "WGluIGNow6Bv")
        #expect(TextTransform.base64Encode.apply("") == "")
        #expect(TextTransform.base64Decode.apply("WGluIGNow6Bv") == "Xin chào")
        // Wrapped lines and surrounding whitespace are common in copied Base64.
        #expect(TextTransform.base64Decode.apply(" xJDhu5NuZyBo4buTIC8g\nMTAwJQ== \n") == "Đồng hồ / 100%")
    }

    @Test func base64DecodeAcceptsBase64URLWithoutPadding() {
        // JWT segments use "-" and "_" and drop the "=" padding.
        #expect(TextTransform.base64Decode.apply("eyJuYW1lIjoixJDhu5NuZyBo4buTIiwicSI6ImE_Yj5jIn0") == #"{"name":"Đồng hồ","q":"a?b>c"}"#)
        #expect(TextTransform.base64Decode.apply("eyJxIjoiPz8-fiJ9") == #"{"q":"??>~"}"#)
        #expect(TextTransform.base64Decode.apply("eyJzdWIiOiIxMjM0IiwibXNnIjoib2s_Pz4ifQ") == #"{"sub":"1234","msg":"ok??>"}"#)
    }

    @Test(arguments: ["WGluIGNow6Bv!", "hello world", "abcde", "a", "%%%%", "/w==", "gA=="])
    func invalidBase64OrNonUTF8IsNotApplicable(input: String) {
        #expect(TextTransform.base64Decode.apply(input) == nil)
    }

    @Test func urlEncodeKeepsOnlyUnreservedCharacters() {
        #expect(TextTransform.urlEncode.apply("a b&c=d/é?#+-._~") == "a%20b%26c%3Dd%2F%C3%A9%3F%23%2B-._~")
        #expect(TextTransform.urlDecode.apply("a%20b%26c%3Dd%2F%C3%A9%3F%23%2B-._~") == "a b&c=d/é?#+-._~")
        #expect(TextTransform.urlDecode.apply("plain text") == "plain text")
    }

    @Test(arguments: ["100%", "%zz", "%E1%BB", "%FF", "a%2"])
    func invalidPercentEncodingIsNotApplicable(input: String) {
        #expect(TextTransform.urlDecode.apply(input) == nil)
    }
}
