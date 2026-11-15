import Foundation

extension FrogArt.Form {
    /// The same made `k` times as big, about `pivot`: the frog that is small enough to sit on a capybara's head.
    func scaled(_ k: Double, about pivot: FrogArt.Point) -> FrogArt.Form {
        func point(_ p: FrogArt.Point) -> FrogArt.Point { (pivot.x + (p.x - pivot.x) * k, pivot.y + (p.y - pivot.y) * k) }
        func blob(_ b: FrogArt.Blob) -> FrogArt.Blob {
            let centre = point((b.cx, b.cy))
            return FrogArt.Blob(centre.x, centre.y, b.rx * k, b.ry * k, angle: b.angle)
        }
        var form = self
        form.body = blob(body)
        form.head = blob(head)
        form.eye = blob(eye)
        form.thigh = blob(thigh)
        form.belly = blob(belly)
        form.chin = blob(chin)
        form.foot = blob(foot)
        form.hind = hind.map(point)
        form.arm = arm.map(point)
        form.tongue = tongue.map(point)
        form.sac = sac * k
        form.sink = sink * k
        return form
    }
}

extension FrogArt {
    // MARK: On the capybara's head

    /// The frog that sits on the head of a capybara that has sunk in the water to its eyes: there are ten rows of the picture over the crown
    /// of its head and no more, and a frog of its usual size is fourteen tall, so it is a smaller frog (`headScale`), the way the cat that
    /// sits on its back is. Everything of it is drawn for a capybara that faces right: its mirror image is the same for one that faces left.
    static let headScale = 0.64
    /// Where its feet are, as a row of the board, and the middle of it as a column, when it sits there: on the crown of the head, which is
    /// the row `CapybaraArt.crown` once the capybara has sunk `CapybaraArt.deepest` rows.
    static let headFeetRow = Double(CapybaraArt.crown + CapybaraArt.deepest) - 2.4
    static let headCentre = 23.0

    /// The frog as it sits on the head: `k` times its size, with its feet on the row `row` of the board and the middle of it at the column
    /// `centre`.
    static func small(_ form: Form, size k: Double = headScale, row: Double = headFeetRow, centre: Double = headCentre) -> PixelFrame {
        draw(rig(form.scaled(k, about: feet).moved(centre - feet.x, row - feet.y)))
    }

    static var headSitFrames: [PixelFrame] {
        (0..<4).map { small(sitForm(breath: Double($0 / 2), eyes: .open).sacked(Double($0 / 2) * 0.7)) }
    }

    static var headBlinkFrames: [PixelFrame] { [Eyes.half, .shut, .shut, .half].map { small(sitForm(eyes: $0)) } }

    /// The hop from the ground to the head, six pictures: the crouch and the push of a frog of its usual size at the foot of the capybara, and
    /// then up in the air it is the smaller frog, rising and landing on the crown of its head. The layer moves under the pictures a few
    /// points a picture, which is why the frog is drawn further right in the picture as it goes up. Faces right: the capybara's head is on
    /// the right of it.
    static var headHopOnFrames: [PixelFrame] {
        let forms = hopForms()
        var land = sitForm(eyes: .open).crouched(0.5)
        land.arm = [(14.2, 17.8), (15.0, 20.0)]
        return [
            picture(forms[0]), picture(forms[1], lift: 1),
            small(forms[2], size: 0.86, row: 13.5, centre: 15.5), small(forms[3], size: 0.76, row: 11.5, centre: 18.5),
            small(forms[4], size: 0.68, row: 9.5, centre: 21), small(land, row: headFeetRow + 0.4),
        ]
    }

    /// The hop back off it, the other way and so facing the other way: it is drawn for a capybara that faces left (its head is on the left of
    /// it), and facing right is how the picture is turned for one that faces right. From the crown of the head it crouches, pushes, and
    /// falls, getting bigger, to the ground at the foot of the capybara.
    static var headHopOffFrames: [PixelFrame] {
        let forms = hopForms()
        let crouch = sitForm(eyes: .open).crouched(0.9)
        return [
            small(crouch, centre: 31 - headCentre), small(forms[1], row: headFeetRow - 0.8, centre: 31 - headCentre + 1),
            small(forms[3], size: 0.7, row: headFeetRow + 0.2, centre: 11.5), small(forms[4], size: 0.78, row: 10, centre: 13.5),
            small(forms[4], size: 0.9, row: 14.5, centre: 15), picture(forms[5]),
        ]
    }
}
