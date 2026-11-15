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
  final String? filePath;

  CloudSyncPayload({
    this.format = 'text/plain',
    required this.content,
    this.sourceApp,
    required this.timestamp,
    this.filePath,
  });

  Map<String, dynamic> toJson() => {
        'format': format,
        'content': content,
        if (sourceApp != null) 'sourceApp': sourceApp,
        'timestamp': timestamp,
        if (filePath != null) 'filePath': filePath,
      };

  factory CloudSyncPayload.fromJson(Map<String, dynamic> json) =>
      CloudSyncPayload(
        format: json['format'] as String? ?? 'text/plain',
        content: json['content'] as String? ?? '',
        sourceApp: json['sourceApp'] as String?,
        timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        filePath: json['filePath'] as String?,
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

/// CloudSync V2 Envelope with authenticated encryption (AAD).
class CloudSyncEnvelopeV2 {
  final String type;
  final int v;
  final String id;
  final String senderId;
  final int timestamp;
  final String nonce;
  final String tag;
  final String ciphertext;

  CloudSyncEnvelopeV2({
    this.type = 'clip_v2',
    this.v = 2,
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

  factory CloudSyncEnvelopeV2.fromJson(Map<String, dynamic> json) =>
      CloudSyncEnvelopeV2(
        type: json['type'] as String? ?? 'clip_v2',
        v: json['v'] as int? ?? 2,
        id: json['id'] as String? ?? '',
        senderId: json['senderId'] as String? ?? 'unknown',
        timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        nonce: json['nonce'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        ciphertext: json['ciphertext'] as String? ?? '',
      );

  String serialize() => jsonEncode(toJson());
}

/// File Chunk transfer payload for V2.
class FileChunkPayload {
  final String kind;
  final String transferId;
  final String senderSessionId;
  final String receiverSessionId;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String fileHash;
  final int sequence;
  final int totalChunks;
  final String contentBase64;

  FileChunkPayload({
    required this.kind,
    required this.transferId,
    required this.senderSessionId,
    required this.receiverSessionId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.fileHash,
    required this.sequence,
    required this.totalChunks,
    required this.contentBase64,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'transfer_id': transferId,
        'sender_session_id': senderSessionId,
        'receiver_session_id': receiverSessionId,
        'file_name': fileName,
        'mime_type': mimeType,
        'file_size': fileSize,
        'file_hash': fileHash,
        'sequence': sequence,
        'total_chunks': totalChunks,
        'content_base64': contentBase64,
      };

  factory FileChunkPayload.fromJson(Map<String, dynamic> json) =>
      FileChunkPayload(
        kind: json['kind'] as String? ?? 'file',
        transferId: json['transfer_id'] as String? ?? '',
        senderSessionId: json['sender_session_id'] as String? ?? '',
        receiverSessionId: json['receiver_session_id'] as String? ?? '',
        fileName: json['file_name'] as String? ?? 'file.bin',
        mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
        fileSize: json['file_size'] as int? ?? 0,
        fileHash: json['file_hash'] as String? ?? '',
        sequence: json['sequence'] as int? ?? 0,
        totalChunks: json['total_chunks'] as int? ?? 1,
        contentBase64: json['content_base64'] as String? ?? '',
      );

  String serialize() => jsonEncode(toJson());
}

