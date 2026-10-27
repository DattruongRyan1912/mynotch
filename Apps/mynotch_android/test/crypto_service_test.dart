import 'package:flutter_test/flutter_test.dart';
import 'package:mynotch_android/models/cloud_sync_models.dart';
import 'package:mynotch_android/services/crypto_service.dart';

void main() {
  group('CryptoService & Envelope Tests', () {
    const testKeyBase64 = 'kQJ2fF+W42tT3oT/v5ZqF2fE1d6p9C0b1A3d5F7h9Jk='; // 32 bytes

    test('Encrypt and Decrypt text roundtrip matches', () async {
      const originalText = 'Xin chào từ Flutter Android! 🚀';

      final envelope = await CryptoService.encrypt(
        text: originalText,
        keyBase64: testKeyBase64,
        senderId: 'android',
        sourceApp: 'Chrome',
      );

      expect(envelope.senderId, 'android');
      expect(envelope.nonce.isNotEmpty, true);
      expect(envelope.tag.isNotEmpty, true);
      expect(envelope.ciphertext.isNotEmpty, true);

      final decrypted = await CryptoService.decrypt(
        envelope: envelope,
        keyBase64: testKeyBase64,
      );

      expect(decrypted.content, originalText);
      expect(decrypted.format, 'text/plain');
      expect(decrypted.sourceApp, 'Chrome');
    });

    test('Every encryption produces a distinct fresh CSPRNG nonce', () async {
      const text = 'Testing unique nonce';

      final env1 = await CryptoService.encrypt(
        text: text,
        keyBase64: testKeyBase64,
        senderId: 'android',
      );

      final env2 = await CryptoService.encrypt(
        text: text,
        keyBase64: testKeyBase64,
        senderId: 'android',
      );

      expect(env1.nonce != env2.nonce, true);
      expect(env1.ciphertext != env2.ciphertext, true);
    });

    test('Parse PairingCredentials from Mac QR URI', () {
      const validUri = 'mynotch://pair?c=test-channel-123&k=auth-token-456&e=aes-key-789&s=wss://relay.mynotch.app/ws';
      final creds = PairingCredentials.parseUri(validUri);

      expect(creds, isNotNull);
      expect(creds!.channelId, 'test-channel-123');
      expect(creds.authToken, 'auth-token-456');
      expect(creds.aesKeyBase64, 'aes-key-789');
      expect(creds.relayServerUrl, 'wss://relay.mynotch.app/ws');
    });
  });

  test('Pairing link keeps the + of a key the Mac leaves unescaped', () {
    // URLComponents on the Mac escapes '=' but not '+'.
    final creds = PairingCredentials.parseUri(
        'mynotch://pair?c=chan12345&k=token12345&e=kQJ2fF+W42tT3oT/v5ZqF2fE1d6p9C0b1A3d5F7h9Jk%3D&s=wss://relay.example/ws');
    expect(creds!.aesKeyBase64, 'kQJ2fF+W42tT3oT/v5ZqF2fE1d6p9C0b1A3d5F7h9Jk=');
  });
}
