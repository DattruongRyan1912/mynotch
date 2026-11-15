import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardCSSColorTests {
    @Test(arguments: [
        // rgb with commas and with spaces, rgba as an alias, any case.
        ("rgb(255, 136, 0)", "#FF8800"),
        ("rgb(255,136,0)", "#FF8800"),
        ("rgb(255 136 0)", "#FF8800"),
        ("rgb( 255 ,  136 , 0 )", "#FF8800"),
        ("RGB(255, 136, 0)", "#FF8800"),
        ("rgba(255, 136, 0)", "#FF8800"),
        ("rgb(255, 136, 0, 1)", "#FF8800"),
        ("rgb(0, 0, 0)", "#000000"),
        ("rgb(+1, 2, 3)", "#010203"),
        ("rgb(255,\n136,\n0)", "#FF8800"),
        // Alpha: 0…1 or a percentage, comma or slash.
        ("rgba(255, 136, 0, 0.5)", "#FF880080"),
        ("rgba(255, 136, 0, .5)", "#FF880080"),
        ("rgba(255, 136, 0, 50%)", "#FF880080"),
        ("rgb(255 136 0 / 0.5)", "#FF880080"),
        ("rgb(255 136 0 / 50%)", "#FF880080"),
        ("rgb(255 136 0/50%)", "#FF880080"),
        ("rgba(0, 0, 0, 0)", "#00000000"),
        ("rgba(0, 0, 0, 1)", "#000000"),
        ("rgba(0, 0, 0, 100%)", "#000000"),
        // Percentages and decimals.
        ("rgb(100%, 50%, 0%)", "#FF8000"),
        ("rgb(100% 0% 0%)", "#FF0000"),
        ("rgb(100% 128 0%)", "#FF8000"),
        ("rgb(127.5, 0, 0)", "#800000"),
        ("rgb(254.4, 0, 0)", "#FE0000"),
        // hsl and hsla.
        ("hsl(0, 100%, 50%)", "#FF0000"),
        ("hsl(120, 100%, 50%)", "#00FF00"),
        ("hsl(240, 100%, 50%)", "#0000FF"),
        ("hsl(210, 50%, 40%)", "#336699"),
        ("hsl(120, 100%, 25%)", "#008000"),
        ("hsl(0, 0%, 100%)", "#FFFFFF"),
        ("hsl(0, 0%, 0%)", "#000000"),
        ("hsl(200, 0%, 50%)", "#808080"),
        ("HSL(210 50% 40%)", "#336699"),
        ("hsl(210 50 40)", "#336699"),
        ("hsl(210, 50%, 40%, 0.5)", "#33669980"),
        ("hsla(210, 50%, 40%, 0.5)", "#33669980"),
        ("hsla(210 50% 40% / 50%)", "#33669980"),
        ("hsla(210, 50%, 40%, 1)", "#336699"),
        // Hue units and wrapping.
        ("hsl(120deg 100% 50%)", "#00FF00"),
        ("hsl(0.5turn, 100%, 50%)", "#00FFFF"),
        ("hsl(200grad 100% 50%)", "#00FFFF"),
        ("hsl(3.14159265rad 100% 50%)", "#00FFFF"),
        ("hsl(360, 100%, 50%)", "#FF0000"),
        ("hsl(480, 100%, 50%)", "#00FF00"),
        ("hsl(-120, 100%, 50%)", "#0000FF"),
        ("hsl(-0.25turn, 100%, 50%)", "#8000FF"),
    ])
    func validColorsBecomeHex(input: String, hex: String) {
        #expect(ClipboardCSSColor.hex(input) == hex)
    }

    @Test(arguments: [
        ("rgb(300, 0, 0)", "#FF0000"),
        ("rgb(-20, 0, 999)", "#0000FF"),
        ("rgb(150%, -10%, 0%)", "#FF0000"),
        ("rgb(1000000000000, 0, 0)", "#FF0000"),
        ("rgba(0, 0, 0, 2)", "#000000"),
        ("rgba(0, 0, 0, -1)", "#00000000"),
        ("rgba(0, 0, 0, 150%)", "#000000"),
        ("rgba(0, 0, 0, -5%)", "#00000000"),
        ("hsl(0, 200%, 50%)", "#FF0000"),
        ("hsl(0, -50%, 50%)", "#808080"),
        ("hsl(0, 100%, 150%)", "#FFFFFF"),
        ("hsl(0, 100%, -20%)", "#000000"),
    ])
    func outOfRangeValuesAreClamped(input: String, hex: String) {
        #expect(ClipboardCSSColor.hex(input) == hex)
    }

    @Test(arguments: [
        // Not a color function.
        "", " ", "rgb", "rgb()", "rgba", "hsv(0, 100%, 50%)", "color(srgb 1 0 0)", "lab(50% 40 59)", "red", "#ff8800",
        // Wrong number of arguments.
        "rgb(255, 136)", "rgb(255 136)", "rgb(255, 136, 0, 0.5, 1)", "rgb(255 136 0 0.5)", "rgb(255 136 0 / 0.5 / 1)",
        "hsl(120, 100%)", "rgb(,,)", "rgb(255,,0)", "rgb(255, 136, 0,)", "rgb(255 136 0 /)",
        // Not a number, or a number written another way.
        "rgb(a, b, c)", "rgb(1e2, 0, 0)", "rgb(0x10, 0, 0)", "rgb(inf, 0, 0)", "rgb(nan, 0, 0)", "rgb(--1, 0, 0)",
        "rgb(1.2.3, 0, 0)", "rgb(., 0, 0)", "rgb(1 %, 0, 0)", "rgb(255px, 0, 0)", "rgb(none 0 0)", "rgb(٢٥٥, 0, 0)",
        "rgba(0, 0, 0, 0.5%%)", "hsl(abc, 100%, 50%)", "hsl(120xyz, 100%, 50%)", "hsl(120, 100%, 50)",
        // The comma syntax keeps one kind of channel and needs % for saturation and lightness.
        "rgb(50%, 100, 0)", "hsl(120, 100, 50)", "hsl(120, 100%, 50)", "hsl(120, 50, 50%)", "hsl(120 100% 50%, 0.5)",
        // Separators of the two syntaxes do not mix.
        "rgb(255 136, 0)", "rgb(255, 136, 0 / 0.5)", "rgb(255, 136 / 0)",
        // Nothing before or after the function, and brackets in place.
        "rgb (255, 136, 0)", "rgb(255, 136, 0", "rgb 255, 136, 0)", "(255, 136, 0)", "rgb(255, 136, 0) x",
        "x rgb(255, 136, 0)", "color: rgb(255, 136, 0);", "rgb(255, 136, 0)) ", "rgb((255), 136, 0)",
        "rgb(255, 136, 0) rgb(0, 0, 0)",
    ])
    func otherTextIsNotAColor(input: String) {
        #expect(ClipboardCSSColor.hex(input) == nil)
    }

    @Test func longTextIsNotTriedAtAll() {
        let padding = String(repeating: " ", count: 200)
        #expect(ClipboardCSSColor.hex("rgb(255," + padding + "136, 0)") == nil)
        #expect(ClipboardCSSColor.hex("rgb(" + String(repeating: "9", count: 400) + ", 0, 0)") == nil)
    }

    @Test func theLongestSensibleColorIsStillRecognized() {
        #expect(ClipboardCSSColor.hex("rgba(255.000000, 255.000000, 255.000000, 0.500000)") == "#FFFFFF80")
        #expect(ClipboardCSSColor.hex("hsla(359.999999deg, 100.0000%, 50.0000%, 99.9999%)") != nil)
    }
}
