import AppKit
import CoreImage
import Foundation

/// Handles device pairing credentials, QR code generation, and configuration persistence.
public struct CloudSyncConfig: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var channelId: String
    public var authToken: String
    public var aesKeyBase64: String
    public var relayServerUrl: String

    public static let defaultRelayUrl = "wss://mynotch-cloud-relay.dattruong1912.workers.dev/ws"

    public init(
        isEnabled: Bool = false,
        channelId: String = UUID().uuidString,
        authToken: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        aesKeyBase64: String = CloudSyncCrypto.exportKeyBase64(CloudSyncCrypto.generateKey()),
        relayServerUrl: String = CloudSyncConfig.defaultRelayUrl
    ) {
        self.isEnabled = isEnabled
        self.channelId = channelId
        self.authToken = authToken
        self.aesKeyBase64 = aesKeyBase64
        self.relayServerUrl = relayServerUrl
    }

    /// Generates the deep link URI containing pairing secrets for the Android QR code scanner.
    public var pairingUri: String {
        var components = URLComponents()
        components.scheme = "mynotch"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "c", value: channelId),
            URLQueryItem(name: "k", value: authToken),
            URLQueryItem(name: "e", value: aesKeyBase64),
            URLQueryItem(name: "s", value: relayServerUrl)
        ]
        return components.url?.absoluteString ?? ""
    }
}

public enum CloudSyncPairingHelper {
    /// Renders a high-resolution NSImage QR code from the pairing URI.
    public static func generateQRCodeImage(from string: String, size: CGSize = CGSize(width: 240, height: 240)) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size.width / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let transformedImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let rep = NSCIImageRep(ciImage: transformedImage)
        let nsImage = NSImage(size: size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
