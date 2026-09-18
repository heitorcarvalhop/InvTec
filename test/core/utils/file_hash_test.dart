import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/utils/file_hash.dart';

void main() {
  group('PROMPT 11.1 — sha256Hex', () {
    test('hash conhecido de "abc" (vetor de teste padrão do SHA-256)', () {
      expect(
        sha256Hex(Uint8List.fromList(utf8.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('conteúdos diferentes produzem hashes diferentes', () {
      final a = sha256Hex(Uint8List.fromList(utf8.encode('documento 1')));
      final b = sha256Hex(Uint8List.fromList(utf8.encode('documento 2')));
      expect(a, isNot(b));
    });

    test('o mesmo conteúdo sempre produz o mesmo hash', () {
      final bytes = Uint8List.fromList(utf8.encode('mesmo conteúdo'));
      expect(sha256Hex(bytes), sha256Hex(bytes));
    });
  });
}
