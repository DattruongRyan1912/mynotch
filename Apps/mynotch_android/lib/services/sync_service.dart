import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/cloud_sync_models.dart';
import 'crypto_service.dart';
import 'file_transfer_service.dart';

enum ConnectionStateEnum { disconnected, connecting, connected, error }

class VerifiedTransferReceipt {
  final String transferId;
  final String fileHash;
  final String senderSessionId;
  final String savedPath;

  const VerifiedTransferReceipt({
    required this.transferId,
    required this.fileHash,
    required this.senderSessionId,
    required this.savedPath,
  });
}

class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._();
  SyncService._();

  final _storage = const FlutterSecureStorage();
  /// Native side: credentials for the senders that run without Flutter, clipboard writes, the copy watcher.
  static const _native = MethodChannel('mynotch/native');
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isDisposed = false;

  PairingCredentials? _credentials;
  PairingCredentials? get credentials => _credentials;

  ConnectionStateEnum _state = ConnectionStateEnum.disconnected;
  ConnectionStateEnum get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  String? _lastSentText;
  String? _lastReceivedText;

  final List<CloudSyncPayload> _history = [];
  List<CloudSyncPayload> get history => List.unmodifiable(_history);

  Future<void> init() async {
    await loadCredentials();
    if (_credentials != null) {
      connect();
    }
  }

  Future<void> loadCredentials() async {
    final channelId = await _storage.read(key: 'channel_id');
    final auth = await _storage.read(key: 'auth_token');
    final key = await _storage.read(key: 'aes_key');
    final server = await _storage.read(key: 'server_url');

    if (channelId != null && auth != null && key != null && server != null) {
      _credentials = PairingCredentials(
        channelId: channelId,
        authToken: auth,
        aesKeyBase64: key,
        relayServerUrl: server,
      );
      await _pushCredentials();
      notifyListeners();
    }
  }

  Future<void> _pushCredentials() => _native.invokeMethod('setCredentials', {
        'channelId': _credentials?.channelId,
        'authToken': _credentials?.authToken,
        'aesKeyBase64': _credentials?.aesKeyBase64,
        'relayServerUrl': _credentials?.relayServerUrl,
        'sessionId': _currentSessionId,
      });

  /// Pairs from a `mynotch://pair` link opened in a debug build (emulators cannot easily scan the QR code).
  Future<void> takePairLink() async {
    final uri = await _native.invokeMethod<String>('takePairUri');
    final creds = uri == null ? null : PairingCredentials.parseUri(uri);
    if (creds != null) await saveCredentials(creds);
  }

  /// State of the automatic sending of copies: enabled, running, and whether READ_LOGS and the overlay are granted.
  Future<Map<String, dynamic>> watchStatus() async =>
      Map<String, dynamic>.from(await _native.invokeMethod('watchStatus'));

  Future<Map<String, dynamic>> setWatch(bool enabled) async =>
      Map<String, dynamic>.from(await _native.invokeMethod('setWatch', {'enabled': enabled}));

  Future<void> saveCredentials(PairingCredentials creds) async {
    _credentials = creds;
    await _storage.write(key: 'channel_id', value: creds.channelId);
    await _storage.write(key: 'auth_token', value: creds.authToken);
    await _storage.write(key: 'aes_key', value: creds.aesKeyBase64);
    await _storage.write(key: 'server_url', value: creds.relayServerUrl);
    await _pushCredentials();
    notifyListeners();
    connect();
  }

  Future<void> clearCredentials() async {
    disconnect();
    _credentials = null;
    await _storage.deleteAll();
    await _pushCredentials();
    _history.clear();
    notifyListeners();
  }

  void connect() {
    if (_credentials == null) return;
    disconnect();

    _state = ConnectionStateEnum.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final baseUri = Uri.parse(_credentials!.relayServerUrl);
      final scheme = (baseUri.scheme == 'https' || baseUri.scheme == 'wss') ? 'wss' : 'ws';
      final wsUri = baseUri.replace(
        scheme: scheme,
        queryParameters: {
          ...baseUri.queryParameters,
          'channel': _credentials!.channelId,
          'auth': _credentials!.authToken,
          'sender': 'android',
        },
      );

      _channel = WebSocketChannel.connect(wsUri);
      _channel!.stream.listen(
        _onMessage,
        onError: (err) {
          _state = ConnectionStateEnum.error;
          _lastError = err.toString();
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          _state = ConnectionStateEnum.disconnected;
          notifyListeners();
          _scheduleReconnect();
        },
      );

      _state = ConnectionStateEnum.connected;
      _currentSessionId = _generateUuid();
      _native.invokeMethod('setSessionId', {'sessionId': _currentSessionId});
      _peerSessionId = null;
      _sendHello();
      _startHeartbeat();
      notifyListeners();
    } catch (e) {
      _state = ConnectionStateEnum.error;
      _lastError = e.toString();
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _currentSessionId = _generateUuid();
    _peerSessionId = null;
    for (final c in _pendingChunkAcks.values) {
      if (!c.isCompleted) c.complete(false);
    }
    _pendingChunkAcks.clear();
    for (final c in _pendingCompleteAcks.values) {
      if (!c.isCompleted) c.complete({});
    }
    _pendingCompleteAcks.clear();
    _state = ConnectionStateEnum.disconnected;
    notifyListeners();
  }

  static String _generateUuid() {
    final rnd = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant RFC 4122
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  String _currentSessionId = _generateUuid();
  String get currentSessionId => _currentSessionId;
  String? _peerSessionId;
  String? get peerSessionId => _peerSessionId;

  final Map<String, VerifiedTransferReceipt> _processedReceipts = {};
  final List<String> _processedReceiptOrder = [];
  static const int _maxProcessedReceipts = 100;

  bool isTransferProcessed(String transferId) => _processedReceipts.containsKey(transferId);
  VerifiedTransferReceipt? getProcessedReceipt(String transferId) => _processedReceipts[transferId];

  void _recordProcessedReceipt(VerifiedTransferReceipt receipt) {
    if (_processedReceipts.containsKey(receipt.transferId)) return;
    _processedReceipts[receipt.transferId] = receipt;
    _processedReceiptOrder.add(receipt.transferId);
    if (_processedReceiptOrder.length > _maxProcessedReceipts) {
      final oldest = _processedReceiptOrder.removeAt(0);
      _processedReceipts.remove(oldest);
    }
  }

  Future<void> sendHello() async {
    if (_credentials == null || _channel == null) return;
    try {
      final helloPayload = jsonEncode({
        'kind': 'hello',
        'session_id': _currentSessionId,
        'senderId': 'android',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final helloEnvelope = await CryptoService.encryptV2(
        plaintext: helloPayload,
        keyBase64: _credentials!.aesKeyBase64,
        senderId: 'android',
      );
      _channel?.sink.add(helloEnvelope.serialize());
    } catch (e) {
      debugPrint('[SyncService] Failed to send hello: $e');
    }
  }

  Future<void> _sendHello() => sendHello();

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_state == ConnectionStateEnum.connected && _channel != null) {
        _channel!.sink.add(jsonEncode({'type': 'ping', 'timestamp': DateTime.now().millisecondsSinceEpoch}));
      }
    });
  }

  void _scheduleReconnect() {
    if (_isDisposed || _credentials == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_state != ConnectionStateEnum.connected) {
        connect();
      }
    });
  }

  final Map<String, ChunkAssembler> _fileAssemblers = {};
  final Map<String, int> _assemblerTimestamps = {};
  final Map<String, Completer<bool>> _pendingChunkAcks = {};
  final Map<String, Completer<Map<String, dynamic>>> _pendingCompleteAcks = {};

  Future<void> _onMessage(dynamic message) async {
    try {
      final String raw;
      if (message is String) {
        raw = message;
      } else if (message is List<int>) {
        raw = utf8.decode(message);
      } else {
        raw = message.toString();
      }
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;

      if (jsonMap['type'] == 'pong') return;

      // Handle CloudSync V2
      if (jsonMap['type'] == 'clip_v2' && _credentials != null) {
        final envelope = CloudSyncEnvelopeV2.fromJson(jsonMap);
        if (envelope.senderId == 'android') return;

        final decryptedJson = await CryptoService.decryptV2(
          envelope: envelope,
          keyBase64: _credentials!.aesKeyBase64,
        );

        final payloadObj = jsonDecode(decryptedJson) as Map<String, dynamic>;
        final kind = payloadObj['kind'] as String? ?? 'text';

        if (kind == 'hello') {
          final peerSession = payloadObj['session_id'] as String?;
          if (peerSession != null && peerSession.isNotEmpty) {
            _peerSessionId = peerSession;
            final readyPayload = jsonEncode({
              'kind': 'ready',
              'session_id': _currentSessionId,
              'peer_session_id': peerSession,
              'senderId': 'android',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
            final readyEnvelope = await CryptoService.encryptV2(
              plaintext: readyPayload,
              keyBase64: _credentials!.aesKeyBase64,
              senderId: 'android',
            );
            _channel?.sink.add(readyEnvelope.serialize());
          }
          return;
        } else if (kind == 'ready') {
          final peerSession = payloadObj['session_id'] as String?;
          if (peerSession != null && peerSession.isNotEmpty) {
            _peerSessionId = peerSession;
          }
          return;
        } else if (kind == 'chunk_ack') {
          final transferId = payloadObj['transfer_id'] as String? ?? '';
          final seq = payloadObj['sequence'] as int? ?? -1;
          final key = '${transferId}_$seq';
          final completer = _pendingChunkAcks.remove(key);
          if (completer != null && !completer.isCompleted) {
            completer.complete(true);
          }
          return;
        } else if (kind == 'complete_ack') {
          final transferId = payloadObj['transfer_id'] as String? ?? '';
          final completer = _pendingCompleteAcks.remove(transferId);
          if (completer != null && !completer.isCompleted) {
            completer.complete(payloadObj);
          }
          return;
        } else if (kind == 'text') {
          final content = payloadObj['content'] as String? ?? '';
          _lastReceivedText = content;
          await _native.invokeMethod('writeClipboard', {'text': content});
          _history.insert(0, CloudSyncPayload(format: 'text/plain', content: content, sourceApp: payloadObj['sourceApp'] as String?, timestamp: envelope.timestamp));
        } else if (kind == 'link') {
          final content = payloadObj['content'] as String? ?? '';
          _lastReceivedText = content;
          await _native.invokeMethod('writeClipboard', {'text': content});
          _history.insert(0, CloudSyncPayload(format: 'text/uri-list', content: content, sourceApp: payloadObj['sourceApp'] as String?, timestamp: envelope.timestamp));
        } else if (kind == 'image') {
          final contentBase64 = payloadObj['content_base64'] as String? ?? '';
          final fileName = payloadObj['file_name'] as String? ?? 'image.png';
          final transferId = payloadObj['transfer_id'] as String?;
          final senderSessionId = payloadObj['sender_session_id'] as String? ?? '';
          final expectedHash = payloadObj['file_hash'] as String? ?? '';
          final receiverSessionId = payloadObj['receiver_session_id'] as String?;

          if (receiverSessionId == null ||
              receiverSessionId.isEmpty ||
              receiverSessionId != _currentSessionId) {
            debugPrint('[SyncService] Image receiver_session_id missing or mismatch: $receiverSessionId != $_currentSessionId, rejecting');
            return;
          }

          if (transferId != null && _processedReceipts.containsKey(transferId)) {
            final receipt = _processedReceipts[transferId]!;
            if (expectedHash.isNotEmpty && expectedHash != receipt.fileHash) {
              debugPrint('[SyncService] Replay tampering detected for image $transferId: incoming $expectedHash != original ${receipt.fileHash}');
              return;
            }
            debugPrint('[SyncService] Image transfer $transferId already processed (replay ignored)');
            await _sendCompleteAck(transferId, receipt.fileHash, senderSessionId: receipt.senderSessionId);
            return;
          }

          if (contentBase64.isNotEmpty) {
            try {
              final imgBytes = base64Decode(contentBase64);
              final computedHash = await CryptoService.sha256Hex(imgBytes);

              if (expectedHash.isNotEmpty && computedHash != expectedHash) {
                debugPrint('[SyncService] Image hash mismatch for transfer $transferId: $computedHash != $expectedHash');
                return;
              }

              final savedPath = await _native.invokeMethod<String>('writeImageClipboard', {
                'base64': contentBase64,
                'fileName': fileName,
              });

              if (savedPath != null && savedPath.isNotEmpty) {
                if (transferId != null) {
                  _recordProcessedReceipt(VerifiedTransferReceipt(
                    transferId: transferId,
                    fileHash: computedHash,
                    senderSessionId: senderSessionId,
                    savedPath: savedPath,
                  ));
                }
                _history.insert(0, CloudSyncPayload(
                  format: 'image/png',
                  content: contentBase64,
                  sourceApp: payloadObj['sourceApp'] as String?,
                  timestamp: envelope.timestamp,
                  filePath: savedPath,
                ));
                if (transferId != null && transferId.isNotEmpty) {
                  await _sendCompleteAck(transferId, computedHash, senderSessionId: senderSessionId);
                }
              }
            } catch (e) {
              debugPrint('[SyncService] Failed to save incoming image: $e');
            }
          }
        } else if (kind == 'file' || kind == 'file_chunk') {
          await _handleIncomingFileChunk(payloadObj, envelope.timestamp);
        }

        if (_history.length > 50) _history.removeLast();
        notifyListeners();
        return;
      }

      // Handle legacy CloudSync V1
      if (jsonMap['type'] == 'clip' && _credentials != null) {
        final envelope = CloudSyncEnvelope.fromJson(jsonMap);

        // Ignore messages sent by ourselves
        if (envelope.senderId == 'android') return;

        final payload = await CryptoService.decrypt(
          envelope: envelope,
          keyBase64: _credentials!.aesKeyBase64,
        );

        // Copy to Android clipboard, through native so the copy watcher knows not to send it back
        _lastReceivedText = payload.content;
        await _native.invokeMethod('writeClipboard', {'text': payload.content});

        _history.insert(0, payload);
        if (_history.length > 50) _history.removeLast();

        notifyListeners();
      }
    } catch (e) {
      debugPrint('[SyncService] Error decoding incoming message: $e');
    }
  }

  Future<void> _handleIncomingFileChunk(Map<String, dynamic> json, int timestamp) async {
    final transferId = json['transfer_id'] as String? ?? '';
    final fileName = json['file_name'] as String? ?? 'file.bin';
    final mimeType = json['mime_type'] as String? ?? 'application/octet-stream';
    final fileSize = json['file_size'] as int? ?? 0;
    final fileHash = json['file_hash'] as String? ?? '';
    final sequence = json['sequence'] as int? ?? 0;
    final totalChunks = json['total_chunks'] as int? ?? 1;
    final contentBase64 = json['content_base64'] as String? ?? '';
    final receiverSessionId = json['receiver_session_id'] as String?;

    if (receiverSessionId == null ||
        receiverSessionId.isEmpty ||
        receiverSessionId != _currentSessionId) {
      debugPrint('[SyncService] File chunk receiver_session_id missing or mismatch: $receiverSessionId != $_currentSessionId, rejecting');
      return;
    }

    // Anti-Replay: if transfer was already completed and saved, re-emit complete_ack with verified receipt and ignore duplicate chunks
    if (_processedReceipts.containsKey(transferId)) {
      final receipt = _processedReceipts[transferId]!;
      if (fileHash.isNotEmpty && fileHash != receipt.fileHash) {
        debugPrint('[SyncService] Replay tampering detected for file $transferId: incoming $fileHash != original ${receipt.fileHash}');
        return;
      }
      debugPrint('[SyncService] File transfer $transferId already processed (replay ignored)');
      await _sendCompleteAck(transferId, receipt.fileHash, senderSessionId: receipt.senderSessionId);
      return;
    }

    // Validate metadata consistency if assembler exists
    final existing = _fileAssemblers[transferId];
    if (existing != null) {
      if (existing.fileName != fileName ||
          existing.fileSize != fileSize ||
          existing.fileHash != fileHash ||
          existing.totalChunks != totalChunks) {
        debugPrint('[SyncService] Metadata mismatch for transfer $transferId, aborting');
        _fileAssemblers.remove(transferId);
        _assemblerTimestamps.remove(transferId);
        return;
      }
    }

    // Prune stale chunk assemblies (> 120s timeout) and bound capacity to max 10
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _assemblerTimestamps[transferId] = nowMs;
    _assemblerTimestamps.removeWhere((tid, ts) {
      if (nowMs - ts > 120000) {
        _fileAssemblers.remove(tid);
        return true;
      }
      return false;
    });
    if (!_fileAssemblers.containsKey(transferId) && _fileAssemblers.length >= 10) {
      final oldestKey = _assemblerTimestamps.entries
          .reduce((a, b) => a.value < b.value ? a : b)
          .key;
      _fileAssemblers.remove(oldestKey);
      _assemblerTimestamps.remove(oldestKey);
    }

    ChunkAssembler assembler;
    try {
      assembler = _fileAssemblers[transferId] ??= ChunkAssembler(
        transferId: transferId,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: fileSize,
        fileHash: fileHash,
        totalChunks: totalChunks,
      );
    } catch (e) {
      debugPrint('[SyncService] ChunkAssembler initialization failed: $e');
      _fileAssemblers.remove(transferId);
      _assemblerTimestamps.remove(transferId);
      await _sendError(transferId, e.toString(), senderSessionId: json['sender_session_id'] as String?);
      return;
    }

    final chunkBytes = base64Decode(contentBase64);
    try {
      assembler.addChunk(sequence: sequence, bytes: chunkBytes);
    } catch (e) {
      debugPrint('[SyncService] addChunk failed: $e');
      _fileAssemblers.remove(transferId);
      _assemblerTimestamps.remove(transferId);
      await _sendError(transferId, e.toString(), senderSessionId: json['sender_session_id'] as String?);
      return;
    }

    // Send chunk_ack back to Mac
    if (_credentials != null && _channel != null) {
      try {
        final ackPayload = jsonEncode({
          'kind': 'chunk_ack',
          'transfer_id': transferId,
          'sequence': sequence,
          'status': 'ok',
        });
        final ackEnvelope = await CryptoService.encryptV2(
          plaintext: ackPayload,
          keyBase64: _credentials!.aesKeyBase64,
          senderId: 'android',
        );
        _channel?.sink.add(ackEnvelope.serialize());
      } catch (_) {}
    }

    if (assembler.isComplete) {
      final completeBytes = await assembler.finalizeAndVerify();
      _fileAssemblers.remove(transferId);
      _assemblerTimestamps.remove(transferId);

      try {
        final savedPath = await _native.invokeMethod<String>('saveAndCopyFile', {
          'transferId': transferId,
          'fileName': fileName,
          'mimeType': mimeType,
          'base64': base64Encode(completeBytes),
        });

        if (savedPath != null && savedPath.isNotEmpty) {
          final receipt = VerifiedTransferReceipt(
            transferId: transferId,
            fileHash: fileHash,
            senderSessionId: json['sender_session_id'] as String? ?? '',
            savedPath: savedPath,
          );
          _recordProcessedReceipt(receipt);
          _history.insert(0, CloudSyncPayload(
            format: 'application/octet-stream',
            content: '$fileName (${(fileSize / 1024).toStringAsFixed(1)} KB)',
            sourceApp: 'Mac',
            timestamp: timestamp,
            filePath: savedPath,
          ));

          await _sendCompleteAck(transferId, receipt.fileHash, senderSessionId: receipt.senderSessionId);
        }
      } catch (e) {
        debugPrint('[SyncService] Failed to save and copy file: $e');
      }
    }
  }

  Future<void> _sendCompleteAck(String transferId, String fileHash, {String senderSessionId = ''}) async {
    if (_credentials == null || _channel == null) return;
    try {
      final completeAckPayload = jsonEncode({
        'kind': 'complete_ack',
        'transfer_id': transferId,
        'sender_session_id': senderSessionId,
        'receiver_session_id': _currentSessionId,
        'file_hash': fileHash,
        'status': 'success',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final completeAckEnvelope = await CryptoService.encryptV2(
        plaintext: completeAckPayload,
        keyBase64: _credentials!.aesKeyBase64,
        senderId: 'android',
      );
      _channel?.sink.add(completeAckEnvelope.serialize());
    } catch (_) {}
  }

  Future<void> _sendError(String transferId, String message, {String? senderSessionId}) async {
    if (_credentials == null || _channel == null) return;
    try {
      final errorPayload = jsonEncode({
        'kind': 'error',
        'transfer_id': transferId,
        'message': message,
        'sender_session_id': _currentSessionId,
        'receiver_session_id': senderSessionId ?? '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final errorEnvelope = await CryptoService.encryptV2(
        plaintext: errorPayload,
        keyBase64: _credentials!.aesKeyBase64,
        senderId: 'android',
      );
      _channel?.sink.add(errorEnvelope.serialize());
    } catch (_) {}
  }

  /// Open or view a local file through Android system viewer.
  Future<bool> openFile(String path) async {
    try {
      final res = await _native.invokeMethod<bool>('openFile', {'path': path});
      return res ?? false;
    } catch (e) {
      debugPrint('[SyncService] Failed to open file: $e');
      return false;
    }
  }

  /// Sends a file or image payload directly across the V2 relay.
  Future<bool> sendFileOrImage({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (_state != ConnectionStateEnum.connected || _credentials == null || _channel == null) {
      return false;
    }
    if (bytes.length > 15 * 1024 * 1024) {
      return false;
    }

    try {
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final isImage = mimeType.startsWith('image/');
      final now = DateTime.now().millisecondsSinceEpoch;

      final transferId = _generateUuid();
      final fileHash = await CryptoService.sha256Hex(bytes);

      if (_peerSessionId == null || _peerSessionId!.isEmpty) {
        await _sendHello();
        for (var i = 0; i < 30; i++) {
          if (_peerSessionId != null && _peerSessionId!.isNotEmpty) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      if (_peerSessionId == null || _peerSessionId!.isEmpty) {
        debugPrint('[SyncService] Cannot send file: peer session not established (handshake incomplete)');
        return false;
      }
      final receiverSessionId = _peerSessionId!;

      if (bytes.length <= 1048576) {
        // Send entire file or image inline in 1 single envelope and wait for complete_ack receipt
        final payload = jsonEncode({
          'kind': isImage ? 'image' : 'file',
          'transfer_id': transferId,
          'sender_session_id': _currentSessionId,
          'receiver_session_id': receiverSessionId,
          'file_name': safeName,
          'mime_type': mimeType,
          'file_size': bytes.length,
          'file_hash': fileHash,
          'sequence': 0,
          'total_chunks': 1,
          'content_base64': base64Encode(bytes),
          'sourceApp': 'Android',
          'timestamp': now,
        });
        final envelope = await CryptoService.encryptV2(
          plaintext: payload,
          keyBase64: _credentials!.aesKeyBase64,
          senderId: 'android',
        );

        final completeCompleter = Completer<Map<String, dynamic>>();
        _pendingCompleteAcks[transferId] = completeCompleter;
        _channel!.sink.add(envelope.serialize());

        try {
          final ack = await completeCompleter.future.timeout(const Duration(seconds: 30));
          final status = ack['status'] as String? ?? '';
          final ackHash = ack['file_hash'] as String? ?? '';
          final ackSenderSession = ack['sender_session_id'] as String?;
          final sessionValid = ackSenderSession != null && ackSenderSession.isNotEmpty && ackSenderSession == _currentSessionId;
          return status == 'success' && ackHash.isNotEmpty && ackHash == fileHash && sessionValid;
        } catch (_) {
          _pendingCompleteAcks.remove(transferId);
          return false;
        }
      }

      // Chunked transfer for files > 1 MiB (512 KiB per chunk) with Window = 1 flow control
      const chunkSize = 524288;
      final totalChunks = ((bytes.length + chunkSize - 1) ~/ chunkSize);

      final completeCompleter = Completer<Map<String, dynamic>>();
      _pendingCompleteAcks[transferId] = completeCompleter;

      for (var seq = 0; seq < totalChunks; seq++) {
        final start = seq * chunkSize;
        final end = (start + chunkSize < bytes.length) ? start + chunkSize : bytes.length;
        final chunk = bytes.sublist(start, end);

        final payload = jsonEncode({
          'kind': 'file_chunk',
          'transfer_id': transferId,
          'sender_session_id': _currentSessionId,
          'receiver_session_id': receiverSessionId,
          'file_name': safeName,
          'mime_type': mimeType,
          'file_size': bytes.length,
          'file_hash': fileHash,
          'sequence': seq,
          'total_chunks': totalChunks,
          'content_base64': base64Encode(chunk),
          'sourceApp': 'Android',
          'timestamp': now,
        });

        final envelope = await CryptoService.encryptV2(
          plaintext: payload,
          keyBase64: _credentials!.aesKeyBase64,
          senderId: 'android',
        );

        final chunkCompleter = Completer<bool>();
        final ackKey = '${transferId}_$seq';
        _pendingChunkAcks[ackKey] = chunkCompleter;
        _channel!.sink.add(envelope.serialize());

        try {
          final acked = await chunkCompleter.future.timeout(const Duration(seconds: 15));
          if (!acked) {
            _pendingChunkAcks.remove(ackKey);
            _pendingCompleteAcks.remove(transferId);
            return false;
          }
        } catch (_) {
          _pendingChunkAcks.remove(ackKey);
          _pendingCompleteAcks.remove(transferId);
          return false;
        }
      }

      // Wait for complete_ack receipt
      try {
        final ack = await completeCompleter.future.timeout(const Duration(seconds: 30));
        final status = ack['status'] as String? ?? '';
        final ackHash = ack['file_hash'] as String? ?? '';
        final ackSenderSession = ack['sender_session_id'] as String?;
        final sessionValid = ackSenderSession != null && ackSenderSession.isNotEmpty && ackSenderSession == _currentSessionId;
        return status == 'success' && ackHash.isNotEmpty && ackHash == fileHash && sessionValid;
      } catch (_) {
        _pendingCompleteAcks.remove(transferId);
        return false;
      }
    } catch (e) {
      debugPrint('[SyncService] Failed to send file: $e');
      return false;
    }
  }

  /// Manually send current Android clipboard to Mac (User initiated).
  /// Checks for copied files/URIs first, otherwise falls back to plain text.
  Future<bool> sendCurrentClipboard() async {
    if (_state != ConnectionStateEnum.connected || _credentials == null || _channel == null) {
      return false;
    }

    try {
      // 1. Check if clipboard contains a file / URI
      try {
        final uriData = await _native.invokeMethod<Map>('readClipboardUriData');
        if (uriData != null) {
          final fileName = uriData['fileName'] as String? ?? 'file.bin';
          final mimeType = uriData['mimeType'] as String? ?? 'application/octet-stream';
          final rawBytes = uriData['bytes'];
          final bytes = (rawBytes is List) ? rawBytes.cast<int>() : null;
          if (bytes != null && bytes.isNotEmpty) {
            return await sendFileOrImage(
              bytes: bytes,
              fileName: fileName,
              mimeType: mimeType,
            );
          }
        }
      } catch (e) {
        debugPrint('[SyncService] Failed checking clipboard URI: $e');
      }

      // 2. Otherwise fall back to plain text
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data == null || data.text == null || data.text!.isEmpty) {
        return false;
      }

      final text = data.text!;
      final envelope = await CryptoService.encryptV2(
        plaintext: jsonEncode({
          'kind': 'text',
          'content': text,
          'sourceApp': 'Android',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
        keyBase64: _credentials!.aesKeyBase64,
        senderId: 'android',
      );

      _channel!.sink.add(envelope.serialize());
      _lastSentText = text;

      _history.insert(
        0,
        CloudSyncPayload(
          format: 'text/plain',
          content: text,
          sourceApp: 'Android (bạn)',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (_history.length > 50) _history.removeLast();

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[SyncService] Failed to send clipboard: $e');
      return false;
    }
  }

  /// Automatically synchronizes the latest Android clipboard to Mac if new content is detected.
  Future<bool> autoSyncIfNew() async {
    if (_state != ConnectionStateEnum.connected || _credentials == null || _channel == null) {
      return false;
    }

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return false;

      // Avoid re-sending if text is identical to last sent or just received from Mac
      if (text == _lastSentText || text == _lastReceivedText) {
        return false;
      }

      return await sendCurrentClipboard();
    } catch (e) {
      debugPrint('[SyncService] autoSyncIfNew error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    disconnect();
    super.dispose();
  }
}
