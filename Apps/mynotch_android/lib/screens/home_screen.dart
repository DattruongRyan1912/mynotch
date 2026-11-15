import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cloud_sync_models.dart';
import '../services/sync_service.dart';
import 'qr_scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _currentClipboardPreview = 'Đang đọc clipboard...';
  bool _autoSendEnabled = true;
  Map<String, dynamic>? _watch;
  Timer? _initTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
    _refreshCurrentClipboard();
    SyncService.instance.takePairLink();
    _refreshWatch();
    // Check initial auto-sync shortly after launch
    _initTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _handleAutoSync();
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('auto_send_enabled')) {
      await prefs.setBool('auto_send_enabled', true);
    }
    if (mounted) {
      setState(() {
        _autoSendEnabled = prefs.getBool('auto_send_enabled') ?? true;
      });
    }
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResume();
    }
  }

  Future<void> _refreshWatch() async {
    final status = await SyncService.instance.watchStatus();
    if (mounted) setState(() => _watch = status);
  }

  Future<void> _handleAppResume() async {
    await SyncService.instance.takePairLink();
    await _refreshWatch();
    await _refreshCurrentClipboard();
    if (SyncService.instance.state != ConnectionStateEnum.connected) {
      SyncService.instance.connect();
    } else {
      await SyncService.instance.sendHello();
    }
    await _handleAutoSync();
  }

  Future<void> _handleAutoSync() async {
    if (!_autoSendEnabled) return;
    final sync = SyncService.instance;
    if (sync.credentials == null) return;

    // Small delay to allow websocket reconnection if waking from sleep
    await Future.delayed(const Duration(milliseconds: 300));
    final success = await sync.autoSyncIfNew();
    if (!mounted) return;
    if (success) {
      await _refreshCurrentClipboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Đã tự động gửi clipboard sang Mac!',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _refreshCurrentClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (mounted) {
        setState(() {
          _currentClipboardPreview = data?.text ?? '(Clipboard trống)';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _currentClipboardPreview = '(Không thể đọc clipboard)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SyncService.instance,
      builder: (context, _) {
        final sync = SyncService.instance;
        final isPaired = sync.credentials != null;

        return Scaffold(
          backgroundColor: const Color(0xFF09090B), // Zinc 950
          appBar: AppBar(
            backgroundColor: const Color(0xFF09090B),
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF27272A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text('✦', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'MyNotch Sync',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            actions: [
              _buildStatusPill(sync.state),
              const SizedBox(width: 16),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await _refreshCurrentClipboard();
              sync.connect();
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                if (!isPaired) _buildPairingPromptCard(context) else _buildActivePairingCard(sync),
                const SizedBox(height: 16),
                _buildSyncActionCard(sync),
                if (isPaired && _watch != null) ...[
                  const SizedBox(height: 16),
                  _buildWatchCard(_watch!),
                ],
                const SizedBox(height: 24),
                _buildHistorySection(sync),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusPill(ConnectionStateEnum state) {
    Color color;
    String label;
    switch (state) {
      case ConnectionStateEnum.connected:
        color = const Color(0xFF10B981);
        label = 'Đã kết nối';
        break;
      case ConnectionStateEnum.connecting:
        color = const Color(0xFFF59E0B);
        label = 'Đang nối...';
        break;
      case ConnectionStateEnum.error:
        color = const Color(0xFFEF4444);
        label = 'Lỗi';
        break;
      case ConnectionStateEnum.disconnected:
        color = const Color(0xFF71717A);
        label = 'Offline';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 3.5, backgroundColor: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPairingPromptCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B), // Zinc 900
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.qr_code_scanner, color: Color(0xFF3B82F6), size: 28),
              SizedBox(width: 12),
              Text(
                'Ghép đôi với MacBook',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Mở MyNotch trên Mac > Cài đặt > Clipboard > bật "Đồng bộ Android" để lấy mã QR ghép đôi bảo mật E2EE.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Quét mã QR từ Mac'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePairingCard(SyncService sync) {
    final creds = sync.credentials!;
    final host = Uri.tryParse(creds.relayServerUrl)?.host ?? creds.relayServerUrl;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF27272A),
            child: Icon(Icons.laptop_mac, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Đã liên kết với Mac',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text('Kênh: ${creds.channelId.substring(0, 8)}... • $host',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 20),
            tooltip: 'Hủy ghép đôi',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF18181B),
                  title: const Text('Hủy ghép đôi?', style: TextStyle(color: Colors.white)),
                  content: const Text('Bạn sẽ cần quét lại mã QR trên Mac để tiếp tục đồng bộ.',
                      style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Xác nhận', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              );
              if (confirm == true) {
                sync.clearCredentials();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncActionCard(SyncService sync) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Clipboard hiện tại trên Android',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white54),
                onPressed: _refreshCurrentClipboard,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              _currentClipboardPreview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, size: 20, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tự động gửi khi mở app',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('Không cần bấm nút khi vừa copy xong',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                Switch(
                  value: _autoSendEnabled,
                  activeThumbColor: const Color(0xFF10B981),
                  onChanged: (val) async {
                    setState(() => _autoSendEnabled = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('auto_send_enabled', val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text(
                'Gửi sang Mac ngay 🚀',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: sync.state == ConnectionStateEnum.connected
                  ? () async {
                      final success = await sync.sendCurrentClipboard();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? '✅ Đã gửi clipboard sang Mac!' : '❌ Không có nội dung để gửi'),
                            backgroundColor: success ? const Color(0xFF10B981) : Colors.redAccent,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        _refreshCurrentClipboard();
                      }
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Automatic sending of every copy, with the one-time adb setup it needs when something is missing.
  Widget _buildWatchCard(Map<String, dynamic> watch) {
    final pkg = watch['packageName'] as String;
    final missing = [
      if (watch['readLogs'] != true) 'adb shell pm grant $pkg android.permission.READ_LOGS',
      if (watch['overlay'] != true) 'adb shell appops set $pkg SYSTEM_ALERT_WINDOW allow',
    ];
    final enabled = watch['enabled'] == true;
    final status = !enabled
        ? 'Tắt'
        : missing.isNotEmpty
            ? 'Thiếu quyền, chưa gửi được'
            : watch['running'] == true
                ? 'Đang chạy'
                : 'Đang khởi động';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tự gửi mỗi lần copy',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Chạy nền • $status', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: const Color(0xFF10B981),
                onChanged: (val) async {
                  final status = await SyncService.instance.setWatch(val);
                  if (mounted) setState(() => _watch = status);
                  // The service reports itself running a moment after it is started.
                  if (val) Future.delayed(const Duration(milliseconds: 500), _refreshWatch);
                },
              ),
            ],
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Cấp một lần từ máy tính (USB debugging), rồi mở lại app:',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            ...missing.map((cmd) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF27272A)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(cmd,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
                        tooltip: 'Sao chép lệnh',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: cmd));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã sao chép lệnh'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection(SyncService sync) {
    if (sync.history.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Chưa có lịch sử đồng bộ.\nSao chép trên Mac hoặc bấm Gửi để bắt đầu!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lịch sử đồng bộ gần đây',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 12),
        ...sync.history.map((item) => _buildHistoryCard(item)),
      ],
    );
  }

  Widget _buildHistoryCard(CloudSyncPayload item) {
    final isFromMac = item.sourceApp != 'Android (bạn)';
    final timeStr = DateTime.fromMillisecondsSinceEpoch(item.timestamp).toLocal().toString().substring(11, 16);
    final isImage = item.format == 'image/png';
    final isLink = item.format == 'text/uri-list';
    final isFile = item.format == 'application/octet-stream';

    IconData typeIcon = isFromMac ? Icons.laptop_mac : Icons.phone_android;
    if (isImage) typeIcon = Icons.photo;
    if (isLink) typeIcon = Icons.link;
    if (isFile) typeIcon = Icons.insert_drive_file;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            typeIcon,
            size: 18,
            color: isFromMac ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.sourceApp ?? (isFromMac ? 'Mac' : 'Android'),
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                if (isImage) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(item.content),
                      height: 80,
                      width: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Text('[Hình ảnh]', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                  ),
                ] else ...[
                  Text(
                    item.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              (isFile || isImage) ? Icons.open_in_new : Icons.copy,
              size: 16,
              color: Colors.white54,
            ),
            tooltip: (isFile || isImage) ? 'Mở tệp' : 'Sao chép',
            onPressed: () async {
              if (item.filePath != null && item.filePath!.isNotEmpty) {
                final opened = await SyncService.instance.openFile(item.filePath!);
                if (!mounted) return;
                if (!opened) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Tệp đã lưu tại: ${item.filePath}'), duration: const Duration(seconds: 2)),
                  );
                }
              } else if (isImage) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ảnh đã được lưu vào bộ nhớ đệm.'), duration: Duration(seconds: 1)),
                );
              } else if (isFile) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Tệp tin ${item.content} đã lưu an toàn trong máy!'), duration: const Duration(seconds: 2)),
                );
              } else {
                Clipboard.setData(ClipboardData(text: item.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép vào clipboard!'), duration: Duration(seconds: 1)),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
