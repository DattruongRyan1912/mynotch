import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/cloud_sync_models.dart';
import 'crypto_service.dart';

enum ConnectionStateEnum { disconnected, connecting, connected, error }

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
      final wsUri = baseUri.replace(
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
    _state = ConnectionStateEnum.disconnected;
    notifyListeners();
  }

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

  Future<void> _onMessage(dynamic message) async {
    try {
      final raw = message.toString();
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;

      if (jsonMap['type'] == 'pong') return;

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

  /// Manually send current Android clipboard to Mac (User initiated)
  Future<bool> sendCurrentClipboard() async {
    if (_state != ConnectionStateEnum.connected || _credentials == null || _channel == null) {
      return false;
    }

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data == null || data.text == null || data.text!.isEmpty) {
        return false;
      }

      final text = data.text!;
      final envelope = await CryptoService.encrypt(
        text: text,
        keyBase64: _credentials!.aesKeyBase64,
        senderId: 'android',
        sourceApp: 'Android',
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
