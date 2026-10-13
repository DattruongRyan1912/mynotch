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
    }

    @Test func trimWhitespaceTrimsTheEndsAndCollapsesSpacesAndTabsInsideLines() {
        #expect(TextTransform.trimWhitespace.apply("\n  a   b \t c  \n\n\t d\t\te \n ") == "a b c\n\nd e")
        #expect(TextTransform.trimWhitespace.apply("one\r\n  two") == "one\ntwo")
        #expect(TextTransform.trimWhitespace.apply("   ") == "")
    }

    @Test func removeEmptyLinesKeepsOtherLinesVerbatim() {
        #expect(TextTransform.removeEmptyLines.apply("a\n\n  b \n \t\nc\r\n\r\nd\n") == "a\n  b \nc\nd")
    }

    @Test func sortLinesUsesLocalizedStandardOrder() {
        #expect(TextTransform.sortLines.apply("item10\nitem2\nBánh\nan") == "an\nBánh\nitem2\nitem10")
        // A trailing line break stays at the end instead of sorting to the top as an empty line.
        #expect(TextTransform.sortLines.apply("b\na\n") == "a\nb\n")
        #expect(TextTransform.sortLines.apply("b\n\na") == "\na\nb")
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

    @Test(arguments: [TextTransform.jsonPretty, .jsonMinify], ["", "hello", "{\"a\": }", "{'a': 1}", "[1, 2", "123", "\"text\""])
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

    @Test(arguments: ["WGluIGNow6B", "WGluIGNow6Bv!", "hello world", "dGVz dA=", "/w==", "gA=="])
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
