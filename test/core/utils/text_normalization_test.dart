import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/utils/text_normalization.dart';

void main() {
  group('PROMPT 10.2.3 — nullIfBlank', () {
    test('null permanece null', () {
      expect(nullIfBlank(null), isNull);
    });

    test('string vazia vira null', () {
      expect(nullIfBlank(''), isNull);
    });

    test('somente espaços vira null', () {
      expect(nullIfBlank('   '), isNull);
    });

    test('tabs/quebras de linha também contam como vazio', () {
      expect(nullIfBlank('\t\n  \t'), isNull);
    });

    test('texto com espaços nas pontas é aparado (trim)', () {
      expect(nullIfBlank(' ABC '), 'ABC');
    });

    test('texto válido sem espaços extras é preservado', () {
      expect(nullIfBlank('DOC-123'), 'DOC-123');
    });

    test('espaços internos são preservados (só as pontas são aparadas)', () {
      expect(nullIfBlank('  Maria Souza  '), 'Maria Souza');
    });
  });
}
