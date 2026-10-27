import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../models/cloud_sync_models.dart';

class CryptoService {
  static final _algorithm = AesGcm.with256bits();

  /// Encrypts plaintext clipboard content into a secure CloudSyncEnvelope with a fresh CSPRNG Nonce.
  static Future<CloudSyncEnvelope> encrypt({
    required String text,
    required String keyBase64,
    required String senderId,
    String? sourceApp,
  }) async {
    final keyBytes = base64Decode(keyBase64);
    final secretKey = SecretKey(keyBytes);

    final payload = CloudSyncPayload(
      format: 'text/plain',
      content: text,
      sourceApp: sourceApp,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final plaintextBytes = utf8.encode(payload.serialize());

    // Generate fresh 12-byte CSPRNG nonce for every message (prevent Nonce Reuse Hazard)
    final nonce = _algorithm.newNonce();

    final secretBox = await _algorithm.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return CloudSyncEnvelope(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: senderId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      nonce: base64Encode(secretBox.nonce),
      tag: base64Encode(secretBox.mac.bytes),
      ciphertext: base64Encode(secretBox.cipherText),
    );
  }

  /// Decrypts an incoming CloudSyncEnvelope back into a CloudSyncPayload.
  static Future<CloudSyncPayload> decrypt({
    required CloudSyncEnvelope envelope,
    required String keyBase64,
  }) async {
    final keyBytes = base64Decode(keyBase64);
    final secretKey = SecretKey(keyBytes);

    final nonce = base64Decode(envelope.nonce);
    final tag = base64Decode(envelope.tag);
    final ciphertext = base64Decode(envelope.ciphertext);

    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(tag),
    );

    final decryptedBytes = await _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    final jsonString = utf8.decode(decryptedBytes);
    final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
    return CloudSyncPayload.fromJson(jsonMap);
  }
}
