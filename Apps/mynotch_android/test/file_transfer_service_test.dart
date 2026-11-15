import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mynotch_android/services/file_transfer_service.dart';

void main() {
  group('FileTransferService Unit Tests', () {
    test('Inline and chunk boundary calculations match contract', () {
      expect(FileTransferService.calculateChunkCount(0), 1);
      expect(FileTransferService.calculateChunkCount(1), 1);
      expect(FileTransferService.calculateChunkCount(1048576), 1);
      expect(FileTransferService.calculateChunkCount(1048577), 3);
      expect(FileTransferService.calculateChunkCount(1572864), 3);
      expect(FileTransferService.calculateChunkCount(15728640), 30);
    });

    test('File size limits (15 MiB)', () {
      expect(FileTransferService.isFileSizeAllowed(15728640), true);
      expect(FileTransferService.isFileSizeAllowed(15728641), false);
    });

    test('Safe file name validation', () {
      expect(FileTransferService.isSafeFileName('../hack.txt'), false);
      expect(FileTransferService.isSafeFileName('/etc/hosts'), false);
      expect(FileTransferService.isSafeFileName('a/b.txt'), false);
      expect(FileTransferService.isSafeFileName('a\x00b.txt'), false);
      expect(FileTransferService.isSafeFileName('.hidden'), false);
      expect(FileTransferService.isSafeFileName('sample.pdf'), true);
      expect(FileTransferService.isSafeFileName('archive.zip'), true);
    });

    test('ChunkAssembler reconstructs complete data and verifies SHA-256', () async {
      final original = utf8.encode('Hello World Android Chunk Assembler!');
      final hashResult = await Sha256().hash(original);
      final hash = hashResult.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final assembler = ChunkAssembler(
        transferId: 'test-transfer-id',
        fileName: 'hello.txt',
        mimeType: 'text/plain',
        fileSize: original.length,
        fileHash: hash,
        totalChunks: 2,
      );

      final mid = original.length ~/ 2;
      final part1 = Uint8List.fromList(original.sublist(0, mid));
      final part2 = Uint8List.fromList(original.sublist(mid));

      assembler.addChunk(sequence: 0, bytes: part1);
      expect(assembler.isComplete, false);

      assembler.addChunk(sequence: 1, bytes: part2);
      expect(assembler.isComplete, true);

      final reconstructed = await assembler.finalizeAndVerify();
      expect(reconstructed, original);
    });

    test('ChunkAssembler rejects tampered duplicate chunk', () {
      final assembler = ChunkAssembler(
        transferId: 'tamper-transfer',
        fileName: 'file.bin',
        mimeType: 'application/octet-stream',
        fileSize: 4,
        fileHash: 'dummy',
        totalChunks: 2,
      );

      assembler.addChunk(sequence: 0, bytes: Uint8List.fromList([1, 2]));
      expect(
        () => assembler.addChunk(sequence: 0, bytes: Uint8List.fromList([99, 99])),
        throwsFormatException,
      );
    });

    test('ChunkAssembler rejects size mismatch on finalize', () async {
      final assembler = ChunkAssembler(
        transferId: 'badsize-transfer',
        fileName: 'file.bin',
        mimeType: 'application/octet-stream',
        fileSize: 10, // Expects 10 bytes
        fileHash: 'dummy',
        totalChunks: 1,
      );

      assembler.addChunk(sequence: 0, bytes: Uint8List.fromList([1, 2, 3])); // Only 3 bytes
      expect(assembler.finalizeAndVerify(), throwsStateError);
    });

    test('ChunkAssembler constructor rejects files > 15 MiB or unsafe names', () {
      expect(
        () => ChunkAssembler(
          transferId: 'overflow-1',
          fileName: 'oversized.bin',
          mimeType: 'application/octet-stream',
          fileSize: 15728641,
          fileHash: 'dummy',
          totalChunks: 31,
        ),
        throwsFormatException,
      );

      expect(
        () => ChunkAssembler(
          transferId: 'traversal-1',
          fileName: '../escaped.txt',
          mimeType: 'text/plain',
          fileSize: 100,
          fileHash: 'dummy',
          totalChunks: 1,
        ),
        throwsFormatException,
      );
    });

    test('Multi-format support (PDF, DOCX, ZIP, PNG, plainText)', () async {
      // PDF
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
      final pdfHash = (await Sha256().hash(pdfBytes)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final pdfAssembler = ChunkAssembler(
        transferId: 'pdf-transfer',
        fileName: 'report.pdf',
        mimeType: 'application/pdf',
        fileSize: pdfBytes.length,
        fileHash: pdfHash,
        totalChunks: 1,
      );
      pdfAssembler.addChunk(sequence: 0, bytes: pdfBytes);
      expect(await pdfAssembler.finalizeAndVerify(), pdfBytes);

      // DOCX / ZIP
      final docxBytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]);
      final docxHash = (await Sha256().hash(docxBytes)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final docxAssembler = ChunkAssembler(
        transferId: 'docx-transfer',
        fileName: 'doc.docx',
        mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        fileSize: docxBytes.length,
        fileHash: docxHash,
        totalChunks: 1,
      );
      docxAssembler.addChunk(sequence: 0, bytes: docxBytes);
      expect(await docxAssembler.finalizeAndVerify(), docxBytes);

      // PNG
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final pngHash = (await Sha256().hash(pngBytes)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final pngAssembler = ChunkAssembler(
        transferId: 'png-transfer',
        fileName: 'photo.png',
        mimeType: 'image/png',
        fileSize: pngBytes.length,
        fileHash: pngHash,
        totalChunks: 1,
      );
      pngAssembler.addChunk(sequence: 0, bytes: pngBytes);
      expect(await pngAssembler.finalizeAndVerify(), pngBytes);
    });
  });
}
