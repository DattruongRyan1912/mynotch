import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mynotch_android/models/cloud_sync_models.dart';
import 'package:mynotch_android/services/crypto_service.dart';
import 'package:mynotch_android/services/sync_service.dart';

void main() {
  group('CloudSync V2 Crypto & Wire Protocol Tests', () {
    test('Cross-platform golden vectors decode correctly', () async {
      final file = File('../../Tests/Fixtures/CloudSyncV2/vectors.json');
      final content = await file.readAsString();
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      final vectors = jsonMap['vectors'] as List<dynamic>;

      expect(vectors.isNotEmpty, true);

      for (final vec in vectors) {
        final keyBase64 = vec['keyBase64'] as String;
        final nonceBase64 = vec['nonceBase64'] as String;
        final tagBase64 = vec['tagBase64'] as String;
        final ctBase64 = vec['ciphertextBase64'] as String;
        final id = vec['id'] as String;
        final senderId = vec['senderId'] as String;
        final timestamp = vec['timestamp'] as int;
        final expectedPlaintext = vec['plaintextJson'] as String;

        final envelope = CloudSyncEnvelopeV2(
          type: 'clip_v2',
          v: 2,
          id: id,
          senderId: senderId,
          timestamp: timestamp,
          nonce: nonceBase64,
          tag: tagBase64,
          ciphertext: ctBase64,
        );

        final decrypted = await CryptoService.decryptV2(
          envelope: envelope,
          keyBase64: keyBase64,
        );

        expect(decrypted, expectedPlaintext);
      }
    });

    test('Encrypt and decrypt roundtrip matches with v2', () async {
      const keyBase64 = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
      const plaintext = '{"kind":"text","content":"Hello Android V2!"}';

      final envelope = await CryptoService.encryptV2(
        plaintext: plaintext,
        keyBase64: keyBase64,
        senderId: 'android',
      );

      expect(envelope.type, 'clip_v2');
      expect(envelope.v, 2);
      expect(envelope.senderId, 'android');

      final decrypted = await CryptoService.decryptV2(
        envelope: envelope,
        keyBase64: keyBase64,
      );

      expect(decrypted, plaintext);
    });

    test('Tampering AAD or Tag causes decryption failure', () async {
      const keyBase64 = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
      const plaintext = '{"kind":"text","content":"Secret"}';

      final envelope = await CryptoService.encryptV2(
        plaintext: plaintext,
        keyBase64: keyBase64,
        senderId: 'android',
      );

      // Tampered senderId alters AAD -> must fail
      final tamperedEnv = CloudSyncEnvelopeV2(
        type: envelope.type,
        v: envelope.v,
        id: envelope.id,
        senderId: 'imposter',
        timestamp: envelope.timestamp,
        nonce: envelope.nonce,
        tag: envelope.tag,
        ciphertext: envelope.ciphertext,
      );

      expect(
        () async => await CryptoService.decryptV2(
          envelope: tamperedEnv,
          keyBase64: keyBase64,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('SyncService Receipt Cache & Replay Protection Tests', () {
    test('VerifiedTransferReceipt preserves verified fields', () {
      final service = SyncService.instance;
      const transferId = 'test-receipt-001';
      expect(service.isTransferProcessed(transferId), false);

      const receipt = VerifiedTransferReceipt(
        transferId: transferId,
        fileHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        senderSessionId: 'session-mac-001',
        savedPath: '/data/user/0/files/sync_files/test-receipt-001/file.bin',
      );

      expect(receipt.transferId, transferId);
      expect(receipt.fileHash, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(receipt.senderSessionId, 'session-mac-001');
      expect(receipt.savedPath, '/data/user/0/files/sync_files/test-receipt-001/file.bin');
    });
  });
}
