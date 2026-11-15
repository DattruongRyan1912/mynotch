import Foundation
import QuartzCore

/// What one character is drawn with in a view: the layer with its picture, the one with what it plays with, and its portal, and what the
/// view has to remember of how it last drew it. A view has one for each character on its stage, in the order the stage draws them in,
/// which is the order of the layers on the view's own.
final class CharacterLayers {
    /// The cat's, or any character's, picture. Anchored at its bottom left corner, so its position is the place of its left foot.
    let sprite: CALayer
    /// The moth or the ball of yarn.
    let prop: CALayer
    /// The portal at the inner edge of a view that is one of two, which opens before the character crosses and closes after.
    let portal: CALayer
    /// The species drawn on them, nil while nobody: one that is another's takes the layers over from the start.
    var species: ObjectIdentifier?
    /// Which leg of its walk the character is on, and the prop on: a leg that says it is over when another has taken its place is not heard.
    var spriteLeg = 0
    var propLeg = 0
    /// Where the character will stand when its leg is over, and the prop: what the next leg goes on from. Not the layer's own value, which
    /// is where the leg began until it says it is over.
    var spriteStands: CGFloat?
    var propStands: CGFloat?
    /// The field the last leg was shown in: where a leg ended is a place in that field and means another in a field that is not the same
    /// (the notch grew, or the other view of the pair has come), so a leg goes on from where the last one ended only in the same one.
    var shownField: CatField?

    init(sprite: CALayer = CALayer(), prop: CALayer = CALayer(), portal: CALayer = CALayer()) {
        self.sprite = sprite
        self.prop = prop
        self.portal = portal
        for layer in all {
            layer.anchorPoint = .zero
            layer.contentsGravity = .resize
            // Nearest neighbour both ways: any other filter smears the pixels.
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            layer.isHidden = true
        }
    }

    var all: [CALayer] { [sprite, prop, portal] }

    /// Whether anything is animating on the layers.
    var isAnimating: Bool {
        all.contains { !($0.animationKeys() ?? []).isEmpty }
    }

    /// Takes the character and every animation away: what a view does when it has nobody to show.
    func stopShowing() {
        spriteLeg += 1
        propLeg += 1
        spriteStands = nil
        propStands = nil
        shownField = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        all.forEach { $0.removeAllAnimations() }
        all.forEach { $0.isHidden = true }
        sprite.zPosition = 0
        prop.zPosition = 0
        CATransaction.commit()
    }
}

/// What a stage hands a view to draw for one character.
struct CharacterDrawing {
    let species: any Species
    let pose: Pose
    /// How long ago the pose began: what makes a view that is shown a pose late play it from where it is.
    let elapsed: TimeInterval
    let appearance: Appearance
}
