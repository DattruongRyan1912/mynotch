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
        /// The PNG bytes of the board's pictures by file name. They go to memory and nowhere else.
        var images: [String: Data]
    }

    enum KeySource: Sendable {
        case password(String)
        /// The board key as the Keychain returned it.
        case key(Data)
    }

    /// Locking an ordinary board: reads the images of `items` from `imagesDirectory`, and seals them all. Throws `.cannotRead` for an
    /// image that cannot be read or is not the file its name says.
    @concurrent static func seal(items: [ClipboardItem], imagesDirectory: URL, key: SymmetricKey, boardID: UUID) async throws -> Data {
        var images: [String: Data] = [:]
        for item in items {
            guard case .image(let image) = item.content, images[image.fileName] == nil else { continue }
            guard image.fileName.wholeMatch(of: /[0-9a-f]{64}\.png/) != nil,
                  let bytes = try? Data(contentsOf: imagesDirectory.appending(path: image.fileName, directoryHint: .notDirectory)) else {
                throw ClipboardVaultError.cannotRead("image")
            }
            images[image.fileName] = bytes
        }
        return try sealNow(items: items, images: images, key: key, boardID: boardID)
    }

    /// Seals `items` with the picture bytes in `images` (an open board's, from memory). `.tooLarge` when the file would be over what a
    /// reader accepts: it could be sealed and never opened.
    static func sealNow(
        items: [ClipboardItem], images: [String: Data], key: SymmetricKey, boardID: UUID, maxBytes: Int = ClipboardVaultFile.maxFileBytes
    ) throws -> Data {
        let names = Set(items.compactMap { item -> String? in
            if case .image(let image) = item.content { image.fileName } else { nil }
        })
        let payload: Data
        do {
            payload = try ClipboardVaultPayload.encode(ClipboardVaultPayload.Contents(items: items, images: images.filter { names.contains($0.key) }))
        } catch ClipboardVaultError.damaged {
            // A picture that is missing, or is not what its name says (damaged).
            throw ClipboardVaultError.cannotRead("image")
        }
        // The header, the nonce and the tag are small beside this; the margin keeps the file under the cap.
        guard payload.count <= maxBytes - ClipboardVaultFile.maxHeaderBytes - 28 else { throw ClipboardVaultError.tooLarge }
        return try ClipboardVaultCrypto.seal(payload, using: key, boardID: boardID, itemCount: items.count)
    }

    /// Opens the vault at `url`: the key (from the password, or as given), the seal, the items and the pictures' bytes. Nothing is
    /// written anywhere: the pictures are handed back to be kept in memory.
    @concurrent static func open(
        at url: URL, boardID: UUID, source: KeySource, policy: ClipboardVaultCrypto.Derivation
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

        return Opened(key: key, envelope: envelope, items: contents.items, images: contents.images)
    }
}

nonisolated extension ClipboardVaultCrypto {
    /// `wrapNewKey` off the main actor: 600,000 rounds take a good part of a second.
    @concurrent static func wrapNewKeyInBackground(password: String, boardID: UUID, using derivation: Derivation) async throws -> PasswordWrapping {
        try wrapNewKey(password: password, boardID: boardID, using: derivation)
    }
}
