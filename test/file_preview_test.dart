import 'dart:convert';
import 'dart:typed_data';

import 'package:drag/fs/file_preview.dart';
import 'package:drag/fs/storage_backend.dart';
import 'package:drag/models/file_item.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_backend.dart';

void main() {
  group('preview predicates', () {
    test('recognise text and image extensions (case-insensitive)', () {
      expect(isTextPreviewable('notes.MD'), isTrue);
      expect(isTextPreviewable('main.dart'), isTrue);
      expect(isTextPreviewable('photo.png'), isFalse);
      expect(isImagePreviewable('photo.PNG'), isTrue);
      expect(isImagePreviewable('archive.zip'), isFalse);
      expect(isPreviewable('a.log'), isTrue);
      expect(isPreviewable('a.bin'), isFalse);
      expect(isPreviewable('noext'), isFalse);
    });
  });

  group('loadPreview', () {
    MemoryBackend backendWith(String path, List<int> bytes) =>
        MemoryBackend(files: {path: Uint8List.fromList(bytes)});

    test('reads a small text file', () async {
      final b = backendWith('/a.txt', utf8.encode('hello world'));
      final p = await loadPreview(
        b,
        '/a.txt',
        const FileItem(name: 'a.txt', sizeBytes: 11),
      );
      expect(p.kind, PreviewKind.text);
      expect(p.text, 'hello world');
      expect(p.truncated, isFalse);
    });

    test('caps a large text file and flags it truncated', () async {
      final big = utf8.encode('x' * 100);
      final b = backendWith('/big.txt', big);
      final p = await loadPreview(
        b,
        '/big.txt',
        const FileItem(name: 'big.txt', sizeBytes: 100),
        maxTextBytes: 10,
      );
      expect(p.kind, PreviewKind.text);
      expect(p.text!.length, 10);
      expect(p.truncated, isTrue);
    });

    test('returns image bytes for a picture under the cap', () async {
      final b = backendWith('/pic.png', [1, 2, 3, 4]);
      final p = await loadPreview(
        b,
        '/pic.png',
        const FileItem(name: 'pic.png', sizeBytes: 4),
      );
      expect(p.kind, PreviewKind.image);
      expect(p.bytes, [1, 2, 3, 4]);
    });

    test('rejects an oversized image up front by its size', () async {
      final b = backendWith('/huge.png', List.filled(100, 0));
      final p = await loadPreview(
        b,
        '/huge.png',
        const FileItem(name: 'huge.png', sizeBytes: 100),
        maxImageBytes: 10,
      );
      expect(p.kind, PreviewKind.tooLarge);
      expect(p.message, contains('too large'));
    });

    test('rejects an oversized image even when its size is unknown', () async {
      final b = backendWith('/u.png', List.filled(100, 0));
      final p = await loadPreview(
        b,
        '/u.png',
        const FileItem(name: 'u.png'), // sizeBytes null
        maxImageBytes: 10,
      );
      expect(p.kind, PreviewKind.tooLarge);
    });

    test('non-text / non-image files report binary', () async {
      final b = MemoryBackend();
      final p = await loadPreview(
        b,
        '/x.bin',
        const FileItem(name: 'x.bin', sizeBytes: 5),
      );
      expect(p.kind, PreviewKind.binary);
      expect(p.message, contains('.bin'));
    });

    test('an empty text file is reported empty without reading', () async {
      final b = MemoryBackend();
      final p = await loadPreview(
        b,
        '/e.txt',
        const FileItem(name: 'e.txt', sizeBytes: 0),
      );
      expect(p.kind, PreviewKind.empty);
    });

    test('surfaces a read error', () async {
      final p = await loadPreview(
        _ThrowingBackend(),
        '/a.txt',
        const FileItem(name: 'a.txt', sizeBytes: 11),
      );
      expect(p.kind, PreviewKind.error);
      expect(p.message, contains('boom'));
    });
  });
}

/// A backend whose reads always fail, to exercise the error path.
class _ThrowingBackend extends MemoryBackend {
  @override
  Future<ReadHandle> openRead(String path) async => throw Exception('boom');
}
