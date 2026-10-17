import AppKit
import MyNotchCore
import SwiftUI

/// How the cat takes a busy Mac.
nonisolated enum BusyReaction: String, CaseIterable, Codable, Sendable {
    /// Now and then: when the load is clearly over what this Mac usually does, for a few seconds, and never more than once in five minutes.
    case occasionally
    case off

    var displayName: String {
        switch self {
        case .occasionally: "Thỉnh thoảng"
        case .off: "Tắt"
        }
    }
}

/// Where the cat plays.
nonisolated enum PlayPlace: String, CaseIterable, Codable, Sendable {
    /// In the top row of the notch: beside the camera on a Mac that has one, where it goes from one side to the other through a portal, and
    /// across the body of a virtual notch. The default.
    case portal
    /// On a strip under a hardware notch, as it was (a virtual notch, which has room, keeps the cat in its body).
    case strip

    var displayName: String {
        switch self {
        case .portal: "Cạnh tai thỏ (cổng dịch chuyển)"
        case .strip: "Dải dưới notch"
        }
    }
}

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct PetSettingsKeys {
    /// The times the cat can be asked to fall asleep after, in minutes.
    static let sleepOptions = [2, 5, 10]

    /// Whether the cat is on the notch. On, which is the point of the module: it turns itself off in Settings, not by default.
    let show: SettingKey<Bool>
    /// The colour of the cat.
    let coat: SettingKey<CatCoat>
    /// A click on the cat mews. Off: a sound nobody asked for at a desk is not a gift.
    let meow: SettingKey<Bool>
    let sleepMinutes: SettingKey<Int>
    /// Whether the cat reacts when the Mac is busy. Now and then, and only to a load that is high for this Mac: on a Mac that is busy all day
    /// a cat that ran on every busy moment would never do anything else.
    let busyReaction: SettingKey<BusyReaction>
    /// Where the cat plays on a screen with a notch cut into it.
    let playPlace: SettingKey<PlayPlace>
    /// Which pets each screen has, by the screen's UUID: a screen that is not in it has a cat.
    let screens: SettingKey<PetScreens>

    init(_ settings: ModuleSettings) {
        show = settings.key("show", default: true)
        coat = settings.key("coat", default: CatCoat.tabby)
        meow = settings.key("meow", default: false)
        sleepMinutes = settings.key("sleepMinutes", default: 5)
        busyReaction = settings.key("busyReaction", default: BusyReaction.occasionally)
        playPlace = settings.key("playPlace", default: PlayPlace.portal)
        screens = settings.key("screens", default: PetScreens())
    }

    /// The sleep time as the cat has it: the option nearest to what is stored, so a value that is not one of the three still means one.
    static func snapped(sleepMinutes stored: Int) -> Int {
        sleepOptions.min { abs($0 - stored) < abs($1 - stored) } ?? 5
    }

    func tuning(_ settings: ModuleSettings) -> CatTuning {
        CatTuning(
            sleepAfter: TimeInterval(Self.snapped(sleepMinutes: settings.value(sleepMinutes))) * 60,
            reactsToBusyMachine: settings.value(busyReaction) == .occasionally
        )
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct PetSettingsView: View {
    let keys: PetSettingsKeys
    let settings: ModuleSettings
    var displays = Displays.system

    var body: some View {
        Group {
            Toggle(isOn: settings.binding(keys.show)) {
                Text("Hiện thú cưng trên notch")
                Text("Thú cưng chơi trên notch khi không có hoạt động nào khác, và nhường chỗ ngay khi có.")
            }
            PetScreensView(screens: settings.binding(keys.screens), displays: displays)
            Picker("Màu mèo", selection: settings.binding(keys.coat)) {
                ForEach(CatCoat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle(isOn: settings.binding(keys.meow)) {
                Text("Tiếng mèo khi bấm")
                Text("Bấm vào mèo để vuốt ve. Mèo kêu thêm một tiếng nếu bật mục này.")
            }
            Picker("Mèo ngủ sau", selection: sleepBinding) {
                ForEach(PetSettingsKeys.sleepOptions, id: \.self) { Text("\($0) phút không đụng tới máy").tag($0) }
            }
            Picker(selection: settings.binding(keys.playPlace)) {
                ForEach(PlayPlace.allCases, id: \.self) { Text($0.displayName).tag($0) }
            } label: {
                Text("Chỗ chơi trên màn có tai thỏ")
                Text("Cạnh tai thỏ: mèo chơi ở hai bên camera và đi từ bên này sang bên kia qua cổng dịch chuyển; hai bên được nới rộng nên che bớt các mục menu cạnh notch. Màn không có tai thỏ luôn cho mèo chơi ngay trong thân notch.")
            }
            Picker(selection: settings.binding(keys.busyReaction)) {
                ForEach(BusyReaction.allCases, id: \.self) { Text($0.displayName).tag($0) }
            } label: {
                Text("Mèo phản ứng khi máy bận")
                Text("Chỉ khi máy bận hơn hẳn mức bình thường của chính nó: mèo chạy cuống một lúc ngắn, tối đa 5 phút một lần.")
            }
        }
    }

    private var sleepBinding: Binding<Int> {
        Binding(
            get: { PetSettingsKeys.snapped(sleepMinutes: settings.value(keys.sleepMinutes)) },
            set: { settings.set($0, for: keys.sleepMinutes) }
        )
    }
}

/// One row for each screen that is connected, with the pets it has: a menu with the characters to tick, as many as the screen has room
/// for, and "Không có" for none. What is ticked is kept at once, under the screen's UUID; the other screens' choices, and those of screens
/// that are not connected, are not touched.
struct PetScreensView: View {
    @Binding var screens: PetScreens
    let displays: Displays
    @State private var connected: [ConnectedDisplay] = []

    var body: some View {
        Group {
            Text("Chọn thú cưng cho từng màn, tối đa \(CharacterKind.maxPerScreen) con mỗi màn. Màn cắm vào lần đầu có một con mèo.")
                .foregroundStyle(.secondary)
            ForEach(connected) { display in
                PetScreenRow(display: display, screens: $screens)
            }
        }
        .onAppear { connected = displays.current() }
        .onReceive(displays.notifications.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            connected = displays.current()
        }
    }
}

struct PetScreenRow: View {
    let display: ConnectedDisplay
    @Binding var screens: PetScreens

    private var kinds: [CharacterKind] { screens.kinds(for: display.id) }

    /// What the menu says: the names of the ones that are ticked.
    static func summary(of kinds: [CharacterKind]) -> String {
        kinds.isEmpty ? "Không có" : kinds.map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        LabeledContent {
            Menu {
                ForEach(CharacterKind.allCases, id: \.self) { kind in
                    Toggle(kind.displayName, isOn: Binding(
                        get: { kinds.contains(kind) },
                        set: { _ in screens = screens.toggling(kind, on: display.id) }
                    ))
                    .disabled(!kinds.contains(kind) && !screens.canAdd(to: display.id))
                }
                Divider()
                Toggle("Không có", isOn: Binding(
                    get: { kinds.isEmpty },
                    set: { if $0 { screens = screens.setting([], for: display.id) } }
                ))
            } label: {
                Text(Self.summary(of: kinds))
            }
            .fixedSize()
        } label: {
            Text(display.name)
            Text(display.kindName)
        }
    }
}
