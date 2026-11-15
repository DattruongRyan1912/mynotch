import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class FileTransferService {
  static const int maxFileSizeBytes = 15728640; // 15 MiB
  static const int inlineThresholdBytes = 1048576; // 1 MiB
  static const int chunkSizeBytes = 524288; // 512 KiB

  static bool isFileSizeAllowed(int fileSize) => fileSize >= 0 && fileSize <= maxFileSizeBytes;

  static int calculateChunkCount(int fileSize, {int chunkSize = chunkSizeBytes}) {
    if (fileSize <= inlineThresholdBytes) return 1;
    return (fileSize / chunkSize).ceil();
  }

  static bool isSafeFileName(String name) {
    if (name.isEmpty) return false;
    if (name == '.' || name == '..') return false;
    if (name.contains('/') || name.contains('\\') || name.contains('\x00')) return false;
    if (name.contains('..')) return false;
    if (name.startsWith('.')) return false;
    if (utf8.encode(name).length > 255) return false;
    return true;
  }
}

class ChunkAssembler {
  final String transferId;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String fileHash;
  final int totalChunks;

  final Map<int, Uint8List> _chunks = {};
  int _nextExpected = 0;

  ChunkAssembler({
    required this.transferId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.fileHash,
    required this.totalChunks,
  }) {
    if (!FileTransferService.isFileSizeAllowed(fileSize)) {
      throw FormatException('File size $fileSize exceeds maximum allowed limit (15 MiB)');
    }
    if (!FileTransferService.isSafeFileName(fileName)) {
      throw FormatException('Invalid or unsafe file name: $fileName');
    }
  }

  bool get isComplete => _chunks.length == totalChunks;
  int get currentBytes => _chunks.values.fold(0, (sum, c) => sum + c.length);

  void addChunk({required int sequence, required Uint8List bytes}) {
    if (sequence < 0 || sequence >= totalChunks) {
      throw FormatException('Sequence $sequence out of bounds [0, $totalChunks)');
    }
    if (_chunks.containsKey(sequence)) {
      final existing = _chunks[sequence]!;
      if (existing.length != bytes.length) {
        throw FormatException('Tampered duplicate chunk $sequence');
      }
      for (int i = 0; i < existing.length; i++) {
        if (existing[i] != bytes[i]) throw FormatException('Tampered duplicate chunk $sequence');
      }
      return; // Idempotent duplicate
    }
    if (currentBytes + bytes.length > fileSize) {
      throw FormatException('Cumulative chunk bytes (${currentBytes + bytes.length}) exceeds declared file size $fileSize');
    }
    if (currentBytes + bytes.length > FileTransferService.maxFileSizeBytes) {
      throw FormatException('Cumulative chunk bytes (${currentBytes + bytes.length}) exceeds 15 MiB limit');
    }
    if (sequence != _nextExpected) {
      throw FormatException('Out of order chunk: expected $_nextExpected, got $sequence');
    }

    _chunks[sequence] = bytes;
    _nextExpected++;
  }

  Future<Uint8List> finalizeAndVerify() async {
    if (!isComplete) {
      throw StateError('Incomplete transfer: ${_chunks.length}/$totalChunks chunks');
    }

    final builder = BytesBuilder(copy: false);
    for (int i = 0; i < totalChunks; i++) {
      final chunk = _chunks[i];
      if (chunk == null) throw StateError('Missing chunk $i');
      builder.add(chunk);
    }

    final fullBytes = builder.toBytes();
    if (fullBytes.length != fileSize) {
      throw StateError('File size mismatch: expected $fileSize bytes, got ${fullBytes.length}');
    }

    final hashResult = await Sha256().hash(fullBytes);
    final computedHash = hashResult.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (computedHash.toLowerCase() != fileHash.toLowerCase()) {
      throw StateError('SHA-256 hash mismatch! Expected $fileHash, got $computedHash');
    }

    return fullBytes;
  }
}
