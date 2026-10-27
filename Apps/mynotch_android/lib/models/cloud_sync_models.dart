import 'dart:convert';

/// Wire format matching the macOS CloudSyncEnvelope exactly.
class CloudSyncEnvelope {
  final String type;
  final int v;
  final String id;
  final String senderId;
  final int timestamp;
  final String nonce;
  final String tag;
  final String ciphertext;

  CloudSyncEnvelope({
    this.type = 'clip',
    this.v = 1,
    required this.id,
    required this.senderId,
    required this.timestamp,
    required this.nonce,
    required this.tag,
    required this.ciphertext,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'v': v,
        'id': id,
        'senderId': senderId,
        'timestamp': timestamp,
        'nonce': nonce,
        'tag': tag,
        'ciphertext': ciphertext,
      };

  factory CloudSyncEnvelope.fromJson(Map<String, dynamic> json) =>
      CloudSyncEnvelope(
        type: json['type'] as String? ?? 'clip',
        v: json['v'] as int? ?? 1,
        id: json['id'] as String? ?? '',
        senderId: json['senderId'] as String? ?? 'unknown',
        timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        nonce: json['nonce'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        ciphertext: json['ciphertext'] as String? ?? '',
      );

  String serialize() => jsonEncode(toJson());
}

/// The inner decrypted payload.
class CloudSyncPayload {
  final String format;
  final String content;
  final String? sourceApp;
  final int timestamp;

  CloudSyncPayload({
    this.format = 'text/plain',
    required this.content,
    this.sourceApp,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'format': format,
        'content': content,
        if (sourceApp != null) 'sourceApp': sourceApp,
        'timestamp': timestamp,
      };

  factory CloudSyncPayload.fromJson(Map<String, dynamic> json) =>
      CloudSyncPayload(
        format: json['format'] as String? ?? 'text/plain',
        content: json['content'] as String? ?? '',
        sourceApp: json['sourceApp'] as String?,
        timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );

  String serialize() => jsonEncode(toJson());
}

/// Pairing credentials extracted from the Mac QR Code.
class PairingCredentials {
  final String channelId;
  final String authToken;
  final String aesKeyBase64;
  final String relayServerUrl;

  PairingCredentials({
    required this.channelId,
    required this.authToken,
    required this.aesKeyBase64,
    required this.relayServerUrl,
  });

  static PairingCredentials? parseUri(String uriString) {
    try {
      final uri = Uri.parse(uriString);
      if (uri.scheme != 'mynotch' || uri.host != 'pair') return null;

      final channel = uri.queryParameters['c'];
      final auth = uri.queryParameters['k'];
      // The Mac leaves '+' of the base64 key unescaped and Dart decodes it as a space; base64 has no spaces.
      final key = uri.queryParameters['e']?.replaceAll(' ', '+');
      final server = uri.queryParameters['s'];

      if (channel == null || auth == null || key == null || server == null) {
        return null;
      }

      return PairingCredentials(
        channelId: channel,
        authToken: auth,
        aesKeyBase64: key,
        relayServerUrl: server,
      );
    } catch (_) {
      return null;
    }
  }
}
