import MyNotchCore
import SwiftUI

/// Preset Studio & Library with CRUD, system preset protection, and reset.
public struct EQPresetLibraryView: View {
    public let state: EqualizerState

    public init(state: EqualizerState) {
        self.state = state
    }

    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var isConfirmingDelete = false
    @State private var isConfirmingReset = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header & Presets Selector
            HStack(spacing: 8) {
                Text("HỒ SƠ EQ")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()

                if let selected = state.selected {
                    if state.isSystemDefault(selected.id) {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                            Text("Hệ thống")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Tùy biến")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            // Quick Preset Selection Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(state.profiles) { profile in
                        Button {
                            state.select(profile.id)
                        } label: {
                            HStack(spacing: 3) {
                                if state.isSystemDefault(profile.id) {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 8))
                                }
                                Text(profile.name)
                                    .font(.system(size: 10, weight: state.selectedID == profile.id ? .semibold : .regular))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(state.selectedID == profile.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("equalizer.preset.\(profile.id.uuidString)")
                    }
                }
            }

            // Presets Picker Row
            HStack(spacing: 8) {
                Picker("Hồ sơ", selection: Binding(
                    get: { state.selectedID ?? UUID() },
                    set: { state.select($0) }
                )) {
                    ForEach(state.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                // Add Flat Profile
                Button {
                    let count = state.profiles.count + 1
                    _ = state.addFlatProfile(named: "Hồ sơ \(count)")
                } label: {
                    Label("Thêm mới", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Tạo hồ sơ phẳng mới")
                .accessibilityIdentifier("equalizer.button.addProfile")

                // Duplicate Selected
                Button {
                    if let selectedID = state.selectedID {
                        _ = state.duplicateProfile(selectedID)
                    }
                } label: {
                    Label("Nhân bản", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.selectedID == nil)
                .help("Tạo bản sao từ hồ sơ hiện tại")

                // Rename Button
                Button {
                    if let selected = state.selected {
                        renameDraft = selected.name
                        isRenaming = true
                    }
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.selectedID == nil || !(state.canRename(state.selectedID!)))
                .help(state.selectedID != nil && !state.canRename(state.selectedID!) ? "Hồ sơ hệ thống không thể đổi tên" : "Đổi tên hồ sơ")

                // Delete Button
                Button {
                    Swift.print("DELETE BUTTON ACTION EXECUTED!")
                    isConfirmingDelete = true
                } label: {
                    Label("Xóa", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.selectedID == nil || !(state.canDelete(state.selectedID!)))
                .help(state.selectedID != nil && !state.canDelete(state.selectedID!) ? "Hồ sơ hệ thống không thể xóa" : "Xóa hồ sơ")
            }

            // Inline Delete Confirmation Bar
            if isConfirmingDelete, let selected = state.selected {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                    Text("Xóa hồ sơ “\(selected.name)”?")
                        .font(.system(size: 11, weight: .medium))

                    Spacer()

                    Button("Xóa") {
                        state.delete(selected.id)
                        isConfirmingDelete = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.red)
                    .controlSize(.small)

                    Button("Hủy") {
                        isConfirmingDelete = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(6)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Inline Rename Bar
            if isRenaming, let selectedID = state.selectedID {
                HStack(spacing: 6) {
                    TextField("Tên mới cho hồ sơ", text: $renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit {
                            commitRename(selectedID)
                        }

                    Button("Lưu") {
                        commitRename(selectedID)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Hủy") {
                        isRenaming = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Reset to Defaults Action Bar
            HStack {
                Spacer()
                Button("Khôi phục tất cả về mặc định") {
                    isConfirmingReset = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .help("Khôi phục danh sách hồ sơ ban đầu (Nhạc, Phim, Họp, Deep Bass) và thông số kỹ thuật")
            }
        }
        .confirmationDialog(
            "Khôi phục cấu hình EQ về mặc định?",
            isPresented: $isConfirmingReset,
            actions: {
                Button("Khôi phục mặc định", role: .destructive) {
                    state.resetToDefaults()
                }
                Button("Hủy", role: .cancel) {}
            },
            message: {
                Text("Tất cả hồ sơ tùy biến sẽ bị đặt lại về 4 mẫu mặc định (Nhạc, Phim, Họp, Deep Bass eqMac) và thông số limiter sẽ đặt về -0.5 dBTP.")
            }
        )
    }

    private func commitRename(_ id: UUID) {
        if state.rename(id, to: renameDraft) {
            isRenaming = false
        }
    }
}
