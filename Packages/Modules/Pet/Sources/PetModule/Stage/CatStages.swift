import MyNotchCore
import NotchUI

/// The cats: one for each kind of notch, which is to say one on the Mac's own notch (a camera in the screen, with the cat beside it or on a
/// strip under it) and one on a virtual one (a pill or a notch drawn on a screen that has none). The two do not share a brain, a lane, the
/// places they must not stop at, a pointer to watch or a click: a cat that is good at one is not made to do the other's job.
///
/// It is by kind and not by display because a kind is what the cat's world depends on, the notch is told which one it is (`NotchGeometry.kind`)
/// and two displays of one kind (two monitors with a pill each) have the same world. They do share a cat, as one screen's two wings do.
///
/// Every stage reads the Mac for itself (the processors keep a baseline between reads, which two stages sharing one would trample), and
/// the settings are applied to both.
struct CatStages {
    let hardware: CatStage
    let virtual: CatStage

    init(hardware: CatStage, virtual: CatStage) {
        self.hardware = hardware
        self.virtual = virtual
    }

    /// A stage each, on one scheduler, reading the real Mac.
    init(scheduler: any Scheduler) {
        self.init(hardware: CatStage(scheduler: scheduler), virtual: CatStage(scheduler: scheduler))
    }

    func stage(for kind: NotchKind) -> CatStage {
        switch kind {
        case .hardware: hardware
        case .virtual: virtual
        }
    }

    /// Both, for what applies to every stage: the user's settings, and stopping.
    var all: [CatStage] { [hardware, virtual] }

    func shutDown() { all.forEach { $0.shutDown() } }
}
