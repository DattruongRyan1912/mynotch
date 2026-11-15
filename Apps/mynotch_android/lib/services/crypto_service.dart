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

  // MARK: - CloudSync V2 with AAD Authentication

  static List<int> computeAADV2({
    required String id,
    required String senderId,
    required int timestamp,
  }) {
    return utf8.encode('mynotch\nclip_v2\n2\n$id\n$senderId\n$timestamp');
  }

  static Future<CloudSyncEnvelopeV2> encryptV2({
    required String plaintext,
    required String keyBase64,
    required String senderId,
    String? id,
    int? timestamp,
    List<int>? customNonce,
  }) async {
    final keyBytes = base64Decode(keyBase64);
    final secretKey = SecretKey(keyBytes);

    final msgId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final time = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final aadBytes = computeAADV2(id: msgId, senderId: senderId, timestamp: time);

    final plaintextBytes = utf8.encode(plaintext);
    final nonce = customNonce ?? _algorithm.newNonce();

    final secretBox = await _algorithm.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
      aad: aadBytes,
    );

    return CloudSyncEnvelopeV2(
      id: msgId,
      senderId: senderId,
      timestamp: time,
      nonce: base64Encode(secretBox.nonce),
      tag: base64Encode(secretBox.mac.bytes),
      ciphertext: base64Encode(secretBox.cipherText),
    );
  }

  static Future<String> decryptV2({
    required CloudSyncEnvelopeV2 envelope,
    required String keyBase64,
  }) async {
    final keyBytes = base64Decode(keyBase64);
    final secretKey = SecretKey(keyBytes);

    final nonce = base64Decode(envelope.nonce);
    final tag = base64Decode(envelope.tag);
    final ciphertext = base64Decode(envelope.ciphertext);

    final aadBytes = computeAADV2(
      id: envelope.id,
      senderId: envelope.senderId,
      timestamp: envelope.timestamp,
    );

    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(tag),
    );

    final decryptedBytes = await _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: aadBytes,
    );

    return utf8.decode(decryptedBytes);
  }

  /// Computes SHA-256 hex string for given bytes
  static Future<String> sha256Hex(List<int> bytes) async {
    final hashResult = await Sha256().hash(bytes);
    return hashResult.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
