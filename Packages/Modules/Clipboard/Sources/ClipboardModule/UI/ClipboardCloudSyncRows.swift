import AppKit
import SwiftUI

/// Settings view rows for End-to-End Encrypted Cloud Sync with Android devices.
public struct ClipboardCloudSyncRows: View {
    @State private var manager = CloudSyncManager.shared
    @State private var showingQRPopover = false
    @State private var showingServerSheet = false
    @State private var customServerUrl = ""

    public init() {}

    public var body: some View {
        Group {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Đồng bộ điện thoại Android (Cloud Sync)")
                        .font(.body)
                    Text("Mã hóa đầu cuối E2EE (AES-256-GCM). Máy chủ trung gian không thể đọc nội dung.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { manager.config.isEnabled },
                    set: { manager.config.isEnabled = $0 }
                ))
                .labelsHidden()
            }

            if manager.config.isEnabled {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(manager.status.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let lastSync = manager.lastSyncDate {
                        Text("• Cập nhật: \(formattedTime(lastSync))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        showingQRPopover.toggle()
                    } label: {
                        Label("Quét mã QR", systemImage: "qrcode")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .popover(isPresented: $showingQRPopover) {
                        pairingQRPopoverView
                    }
                }

                HStack {
                    Text("Máy chủ: \(displayHost)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Đổi máy chủ") {
                        customServerUrl = manager.config.relayServerUrl
                        showingServerSheet = true
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .sheet(isPresented: $showingServerSheet) {
                    serverConfigSheet
                }
            }
        }
    }

    private var statusColor: Color {
        switch manager.status {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var displayHost: String {
        URL(string: manager.config.relayServerUrl)?.host ?? manager.config.relayServerUrl
    }

    private var pairingQRPopoverView: some View {
        VStack(spacing: 12) {
            Text("Ghép đôi với Android")
                .font(.headline)

            if let qrImage = CloudSyncPairingHelper.generateQRCodeImage(from: manager.config.pairingUri) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(4)
            } else {
                Text("Không thể tạo mã QR")
                    .foregroundColor(.secondary)
            }

            Text("Mở app MyNotch trên điện thoại Android\nvà quét mã này để đồng bộ.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Tạo mã ghép đôi mới") {
                manager.config = CloudSyncConfig(
                    isEnabled: true,
                    relayServerUrl: manager.config.relayServerUrl
                )
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 240)
    }

    private var serverConfigSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cấu hình máy chủ Cloud Relay")
                .font(.headline)

            Text("Nhập URL WebSocket máy chủ trung gian (Cloudflare Worker hoặc Local Relay):")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("wss://mynotch-cloud-relay.dattruong1912.workers.dev/ws", text: $customServerUrl)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Mặc định") {
                    customServerUrl = CloudSyncConfig.defaultRelayUrl
                }
                Spacer()
                Button("Hủy") {
                    showingServerSheet = false
                }
                Button("Lưu") {
                    manager.config.relayServerUrl = customServerUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    showingServerSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
