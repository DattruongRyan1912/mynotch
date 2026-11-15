import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// What the tab can ask the module to do, so the view needs no module.
struct EqualizerTabActions {
    /// Each time the tab shows.
    let appeared: () -> Void
    let openSettings: () -> Void
    let retry: () -> Void

    func perform(_ action: EqualizerStatus.Action) {
        switch action {
        case .openSettings: openSettings()
        case .retry: retry()
        }
    }
}

/// The "Âm thanh" tab: the profile and the switch on top, the preamp, the ten bands, and one line about what the EQ is doing.
struct EqualizerTabView: View {
    /// What the content needs, with no room to spare: every state of the status line has the same height, so nothing moves when it
    /// changes. A test checks it at the narrowest notch.
    static let contentHeight: CGFloat = 184
    /// The tab bar's height when there are two or more tabs; `NotchTab.preferredHeight` includes it.
    static let tabBarHeight: CGFloat = 30
    static var preferredHeight: CGFloat { contentHeight + NotchTokens.padding + tabBarHeight }
    static let spacing: CGFloat = 6

    let state: EqualizerState
    let status: EqualizerStatus
    let actions: EqualizerTabActions

    @Environment(\.notch) private var notch
    /// A menu of this app is being tracked: the profile list. It lives outside the notch's reach, so a click there counts as
    /// outside and the notch stays pinned while it is open.
    @State private var isMenuOpen = false

    var body: some View {
        VStack(spacing: Self.spacing) {
            EQProfileBar(state: state)
            EQPreampRow(state: state)
            EQBandSliders(state: state)
            EQStatusLine(status: status, actions: actions)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The classic notch is black whatever the system appearance; on Liquid Glass the tab follows the glass.
        .notchColorScheme()
        .onAppear(perform: actions.appeared)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isMenuOpen = true
            notch.setPinned(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isMenuOpen = false
            notch.setPinned(false)
        }
        .onDisappear { if isMenuOpen { notch.setPinned(false) } }
    }
}

/// What the profile row is doing: showing the list, asking for a new name, or asking before a delete.
enum ProfileEdit: Equatable {
    case choosing
    case renaming(UUID)
    case confirmingDelete(UUID)

    /// A profile is chosen or deleted somewhere else: what was being done to another one is moot. Adding a profile selects it
    /// and starts renaming it in the same step, which this keeps.
    func afterSelection(_ selected: UUID?) -> ProfileEdit {
        switch self {
        case .choosing: .choosing
        case .renaming(let target), .confirmingDelete(let target): target == selected ? self : .choosing
        }
    }
}

/// The profile list, add, rename and delete, and the switch. Renaming and the question before a delete take the place of the
/// list in the same row, so there is no alert or sheet outside the notch to keep it open for.
private struct EQProfileBar: View {
    static let height: CGFloat = 24
    static let nameWidth: CGFloat = 150

    let state: EqualizerState

    @State private var mode = ProfileEdit.choosing
    @State private var draft = ""
    @State private var nameRejected = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            switch mode {
            case .choosing: chooser
            case .renaming(let id): renamer(id)
            case .confirmingDelete(let id): confirmer(id)
            }
        }
        .frame(height: Self.height)
        .onChange(of: state.selectedID) { mode = mode.afterSelection(state.selectedID) }
    }

    private var chooser: some View {
        Group {
            Menu {
                if state.profiles.isEmpty {
                    Button("Chưa có hồ sơ") {}.disabled(true)
                }
                ForEach(state.profiles) { profile in
                    Toggle(profile.name, isOn: Binding(
                        get: { profile.id == state.selectedID },
                        set: { if $0 { state.select(profile.id) } }
                    ))
                }
            } label: {
                HStack(spacing: 4) {
                    Text(state.selected?.name ?? "Chưa có hồ sơ")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(NotchTokens.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .frame(maxWidth: Self.nameWidth)
                .background(Capsule().fill(NotchTokens.fill(0.12)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Hồ sơ EQ")
            iconButton("plus", "Thêm hồ sơ", action: add)
            iconButton("pencil", "Đổi tên hồ sơ", enabled: state.selected != nil) {
                if let selected = state.selected { beginRename(selected) }
            }
            iconButton("minus", "Xoá hồ sơ", enabled: state.selected != nil) {
                if let selected = state.selected { mode = .confirmingDelete(selected.id) }
            }
            Spacer(minLength: 8)
            Text("EQ")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
            Toggle("EQ", isOn: Binding(get: { state.isEnabled }, set: { state.isEnabled = $0 }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private func renamer(_ id: UUID) -> some View {
        Group {
            TextField("Tên hồ sơ", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.primaryText)
                .focused($nameFocused)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(NotchTokens.fill(0.12)))
                .overlay(Capsule().stroke(Color.red.opacity(nameRejected ? 0.9 : 0), lineWidth: 1))
                .onSubmit { commitRename(id) }
                .onExitCommand { mode = .choosing }
                .onChange(of: draft) { nameRejected = false }
                .onAppear { nameFocused = true }
                .accessibilityLabel("Tên hồ sơ")
            textButton("Lưu") { commitRename(id) }
            textButton("Huỷ") { mode = .choosing }
        }
    }

    private func confirmer(_ id: UUID) -> some View {
        Group {
            Text("Xoá hồ sơ “\(state.profiles.first { $0.id == id }?.name ?? "")”?")
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            textButton("Xoá", tint: .red) {
                state.delete(id)
                mode = .choosing
            }
            textButton("Huỷ") { mode = .choosing }
        }
    }

    /// A copy of the selected profile under a name the user can change at once.
    private func add() {
        guard let profile = state.addProfile(named: "Hồ sơ \(state.profiles.count + 1)") else { return }
        beginRename(profile)
    }

    private func beginRename(_ profile: EQProfile) {
        draft = profile.name
        nameRejected = false
        mode = .renaming(profile.id)
    }

    /// A name that is empty or too long stays in the field, marked, for the user to fix.
    private func commitRename(_ id: UUID) {
        if state.rename(id, to: draft) {
            mode = .choosing
        } else {
            nameRejected = true
        }
    }

    private func iconButton(_ symbol: String, _ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(NotchTokens.fill(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(label)
        .accessibilityLabel(label)
    }

    private func textButton(_ title: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint ?? NotchTokens.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(NotchTokens.fill(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The preamp slider with its number, and the way back to a flat curve.
private struct EQPreampRow: View {
    static let height: CGFloat = 18

    let state: EqualizerState

    var body: some View {
        let preamp = state.selected?.preamp ?? 0
        HStack(spacing: 8) {
            Text("Preamp")
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .frame(width: 44, alignment: .leading)
            GainSlider(axis: .horizontal, value: preamp, name: "Preamp", range: EQProfile.preampRange, set: { state.setPreamp($0) })
                .frame(height: 14)
                .opacity(state.selected == nil ? 0.4 : 1)
                .disabled(state.selected == nil)
            Text(GainFormat.text(preamp))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTokens.primaryText)
                .frame(width: 58, alignment: .trailing)
            Button("Về phẳng") { state.resetSelectedToFlat() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 18)
                .background(Capsule().fill(NotchTokens.fill(0.12)))
                .disabled(state.selected == nil)
                .opacity(state.selected == nil ? 0.4 : 1)
        }
        .frame(height: Self.height)
    }
}

/// One line about the EQ: what it is doing, or what is in its way and the buttons to deal with it. Two lines of text at most, and
/// always the same height, so a change of state moves nothing above it.
struct EQStatusLine: View {
    static let height: CGFloat = 30

    let status: EqualizerStatus
    let actions: EqualizerTabActions
    /// Two, which is what fits; a test lifts it to see whether the texts need more.
    var lineLimit: Int? = 2

    var body: some View {
        let line = status.line
        HStack(spacing: 8) {
            Image(systemName: line.isWarning ? "exclamationmark.triangle.fill" : "waveform")
                .font(.system(size: 11))
                .foregroundStyle(line.isWarning ? Color.orange : NotchTokens.secondaryText)
            Text(line.text)
                .font(.system(size: 11))
                .foregroundStyle(line.isWarning ? NotchTokens.primaryText : NotchTokens.secondaryText)
                .lineLimit(lineLimit)
                .layoutPriority(1)
                .help(line.text)
            Spacer(minLength: 4)
            ForEach(line.actions, id: \.self) { action in
                Button(action.title) { actions.perform(action) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchTokens.primaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(NotchTokens.fill(0.14)))
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: lineLimit == nil ? nil : Self.height)
        .accessibilityElement(children: .contain)
    }
}
