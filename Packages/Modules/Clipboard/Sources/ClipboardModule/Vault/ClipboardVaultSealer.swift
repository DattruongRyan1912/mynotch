import CryptoKit
import Foundation

/// Putting a board's items into a seal and taking them out, with the image files they need. The slow and large parts, so they run
/// off the main actor.
nonisolated enum ClipboardVaultSealer {
    /// What a board gave when it was opened.
    struct Opened: Sendable {
        var key: SymmetricKey
        var envelope: ClipboardVaultEnvelope
        var items: [ClipboardItem]
        /// The image files this opening made, which are removed again if the board is not opened after all.
        var createdImages: [URL]
    }

    enum KeySource: Sendable {
        case password(String)
        /// The board key as the Keychain returned it.
        case key(Data)
    }

    /// Reads the images of `items` from `imagesDirectory`, and seals them all. Throws `.cannotRead` for an image that cannot be read
    /// or is not the file its name says.
    @concurrent static func seal(items: [ClipboardItem], imagesDirectory: URL, key: SymmetricKey, boardID: UUID) async throws -> Data {
        try sealNow(items: items, imagesDirectory: imagesDirectory, key: key, boardID: boardID)
    }

    static func sealNow(items: [ClipboardItem], imagesDirectory: URL, key: SymmetricKey, boardID: UUID) throws -> Data {
        var images: [String: Data] = [:]
        for item in items {
            guard case .image(let image) = item.content, images[image.fileName] == nil else { continue }
            guard image.fileName.wholeMatch(of: /[0-9a-f]{64}\.png/) != nil,
                  let bytes = try? Data(contentsOf: imagesDirectory.appending(path: image.fileName, directoryHint: .notDirectory)) else {
                throw ClipboardVaultError.cannotRead("image")
            }
            images[image.fileName] = bytes
        }
        let payload: Data
        do {
            payload = try ClipboardVaultPayload.encode(ClipboardVaultPayload.Contents(items: items, images: images))
        } catch ClipboardVaultError.damaged {
            // An image file that is not what its name says (damaged on disk).
            throw ClipboardVaultError.cannotRead("image")
        }
        return try ClipboardVaultCrypto.seal(payload, using: key, boardID: boardID, itemCount: items.count)
    }

    /// Opens the vault at `url`: the key (from the password, or as given), the seal, the items, and the image files, written to
    /// `imagesDirectory` last, so a wrong password or a damaged file writes nothing.
    @concurrent static func open(
        at url: URL, boardID: UUID, source: KeySource, policy: ClipboardVaultCrypto.Derivation, imagesDirectory: URL
    ) async throws -> Opened {
        let file = try ClipboardVaultFile.read(at: url)
        let envelope = file.envelope
        guard envelope.boardID == boardID else { throw ClipboardVaultError.damaged }
        let key: SymmetricKey
        switch (source, envelope.method) {
        case (.password(let password), .password):
            guard let derivation = envelope.derivation, let wrapped = envelope.wrappedKey else { throw ClipboardVaultError.damaged }
            key = try ClipboardVaultCrypto.unwrapKey(
                password: password, derivation: derivation, wrappedKey: wrapped, boardID: boardID, policy: policy
            )
        case (.key(let data), .touchID):
            guard data.count == ClipboardVaultCrypto.keyLength else { throw ClipboardVaultError.damaged }
            key = SymmetricKey(data: data)
        default:
            throw ClipboardVaultError.wrongMethod
        }
        let plaintext = try ClipboardVaultCrypto.open(file.sealed, using: key, boardID: boardID, itemCount: envelope.itemCount)
        let contents = try ClipboardVaultPayload.decode(plaintext)
        guard contents.items.count == envelope.itemCount else { throw ClipboardVaultError.damaged }

        var created: [URL] = []
        do {
            for (name, bytes) in contents.images.sorted(by: { $0.key < $1.key }) {
                let target = imagesDirectory.appending(path: name, directoryHint: .notDirectory)
                let existed = FileManager.default.fileExists(atPath: target.path(percentEncoded: false))
                try ClipboardStore.writeImage(bytes, named: name, in: imagesDirectory)
                if !existed { created.append(target) }
            }
        } catch {
            for url in created { try? FileManager.default.removeItem(at: url) }
            throw ClipboardVaultError.cannotWrite(error.localizedDescription)
        }
        return Opened(key: key, envelope: envelope, items: contents.items, createdImages: created)
    }
}

nonisolated extension ClipboardVaultCrypto {
    /// `wrapNewKey` off the main actor: 600,000 rounds take a good part of a second.
    @concurrent static func wrapNewKeyInBackground(password: String, boardID: UUID, using derivation: Derivation) async throws -> PasswordWrapping {
        try wrapNewKey(password: password, boardID: boardID, using: derivation)
    }
}
