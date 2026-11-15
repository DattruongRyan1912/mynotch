import Foundation

// MARK: The cat on the capybara's back

extension CatArt {
    /// Where the cat's feet are when it sits on the capybara's back: the row of the board, which is the one two above the line round the back
    /// (`CapybaraArt.backTop`), so that the cat's rim and the capybara's are the one rim.
    static let perchFeet = CapybaraArt.backTop - 2

    /// A small cat facing the viewer, 11 pixels wide and `perchFeet + 1` tall: with the room the capybara leaves under the top of the strip,
    /// the cat that sits on it is a cat drawn smaller, as one is that is far off.
    static func miniSit(blink: Bool = false, tail: Bool = true) -> PixelFrame {
        var rows = [
            "KK.......KK",
            "KPK.....KPK",
            "KOOKKKKKOOK",
            "KOOOOOOOOOK",
            "KOEOOOOOEOK",
            "KOOOOPOOOOK",
            ".KOOOOOOOK.",
            "KOOWWWWWOOK",
            "KOOOWWWOOOK",
            "KWWOWWWOWWK",
            ".KKKKKKKKK.",
        ]
        if blink { rows[4] = "KOKOOOOOKOK" }
        var c = CatCanvas()
        c.piece(rows, x: 5, y: 0)
        if tail { c.piece(["KK", "KOO", "KK."], x: 2, y: 7) }
        return c.frame.rimmed(with: "R")
    }

    /// The same lying like a loaf: its paws under it and its head on them.
    static func miniLoaf(squint: Bool = false) -> PixelFrame {
        var rows = [
            "KK.......KK",
            "KPK.....KPK",
            "KOOKKKKKOOK",
            "KOEOOOOOEOK",
            "KOOOOPOOOOK",
            "KOOWWWWWOOK",
            "KOOOOOOOOOK",
            "KKKKKKKKKKK",
        ]
        if squint { rows[3] = "KOKOOOOOKOK" }
        var c = CatCanvas()
        c.piece(rows, x: 5, y: perchFeet - 7)
        c.piece(["KK", "KOO", "KK."], x: 2, y: perchFeet - 3)
        return c.frame.rimmed(with: "R")
    }

    /// A small cat curled up in the air, `rows` above where it sits on the capybara.
    static func miniTucked(rows: Int) -> PixelFrame {
        let picture = [
            "KK.....KK",
            "KPK...KPK",
            "KOOKKKOOK",
            "KOEOOOEOK",
            "KOOOPOOOK",
            "KOOWWWOOK",
            "KWOOOOOWK",
            ".KKKKKKK.",
        ]
        var c = CatCanvas()
        c.piece(picture, x: 6, y: perchFeet - 7 - rows)
        return c.frame.rimmed(with: "R")
    }

    /// The hop onto the capybara, five pictures: the crouch and the spring of the cat's own pounce, the cat curled up and rising, and
    /// landing small on the back. It is facing right; the mirror image faces left.
    static var hopOnFrames: [PixelFrame] {
        let pounce = pounceFrames
        return [pounce[0], pounce[5], miniTucked(rows: 3), miniTucked(rows: 2), miniSit(blink: true)]
    }

    /// The hop off it, four pictures: crouching on the back, curled up in the air, stretched out coming down, and landing.
    static var hopOffFrames: [PixelFrame] {
        let pounce = pounceFrames
        return [miniSit(blink: true), miniTucked(rows: 1), pounce[6], pounce[7]]
    }

    static var perchFrames: [PixelFrame] { [miniSit(), miniSit(), miniSit(blink: true), miniSit()] }

    static var perchLoafFrames: [PixelFrame] { [miniLoaf(), miniLoaf(squint: true)] }
}
