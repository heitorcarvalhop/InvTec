import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/tombamento_normalizacao.dart';

void main() {
  group('normalizarTombamentoParaComparacao — numérico', () {
    test('zeros à esquerda não entram na chave de comparação', () {
      expect(
        normalizarTombamentoParaComparacao('000123456').chaveComparacao,
        '123456',
      );
      expect(
        normalizarTombamentoParaComparacao('00123456').chaveComparacao,
        '123456',
      );
      expect(
        normalizarTombamentoParaComparacao('123456').chaveComparacao,
        '123456',
      );
      expect(
        normalizarTombamentoParaComparacao('000504797').chaveComparacao,
        '504797',
      );
      expect(
        normalizarTombamentoParaComparacao('003636971').chaveComparacao,
        '3636971',
      );
      expect(
        normalizarTombamentoParaComparacao('000000001').chaveComparacao,
        '1',
      );
    });

    test('zeros internos são preservados', () {
      expect(
        normalizarTombamentoParaComparacao('001020304').chaveComparacao,
        '1020304',
      );
    });

    test('zeros finais são preservados', () {
      expect(
        normalizarTombamentoParaComparacao('000123400').chaveComparacao,
        '123400',
      );
    });

    test('classifica como numerico e preserva o original (com trim)', () {
      final r = normalizarTombamentoParaComparacao('  000123456  ');
      expect(r.tipo, TombamentoTipo.numerico);
      expect(r.original, '000123456');
      expect(r.chaveComparacao, '123456');
    });

    test('nunca converte para int/double (resultado continua String)', () {
      final r = normalizarTombamentoParaComparacao('000123456');
      expect(r.chaveComparacao, isA<String>());
      expect(r.chaveComparacao, '123456');
    });
  });

  group('normalizarTombamentoParaComparacao — vazio / só zeros / inválido', () {
    test('tombamento vazio (null) é classificado como vazio, chave nula', () {
      final r = normalizarTombamentoParaComparacao(null);
      expect(r.tipo, TombamentoTipo.vazio);
      expect(r.chaveComparacao, isNull);
    });

    test(
      'tombamento vazio (string vazia/só espaços) é classificado como vazio',
      () {
        expect(
          normalizarTombamentoParaComparacao('').tipo,
          TombamentoTipo.vazio,
        );
        expect(
          normalizarTombamentoParaComparacao('   ').tipo,
          TombamentoTipo.vazio,
        );
      },
    );

    test(
      'tombamento só com zeros é inválido, nunca "zero" como chave válida',
      () {
        for (final valor in ['0', '00', '000000']) {
          final r = normalizarTombamentoParaComparacao(valor);
          expect(r.tipo, TombamentoTipo.somenteZeros, reason: valor);
          expect(r.chaveComparacao, isNull, reason: valor);
        }
      },
    );

    test(
      'valor não numérico (ex.: legado alfanumérico) não tem zeros removidos',
      () {
        final r = normalizarTombamentoParaComparacao('TI-769');
        expect(r.tipo, TombamentoTipo.naoNumerico);
        expect(r.chaveComparacao, 'TI-769');
      },
    );

    test(
      'valor não numérico é comparado sem distinguir maiúsculas/minúsculas',
      () {
        expect(
          normalizarTombamentoParaComparacao('ti-769').chaveComparacao,
          normalizarTombamentoParaComparacao('TI-769').chaveComparacao,
        );
      },
    );
  });

  group('tombamentosSaoEquivalentes', () {
    test(
      'BUG REAL: mesma série de exemplos do pedido — todos equivalentes entre si',
      () {
        const valores = ['000123456', '00123456', '123456'];
        for (final a in valores) {
          for (final b in valores) {
            expect(
              tombamentosSaoEquivalentes(a, b),
              isTrue,
              reason: '$a vs $b',
            );
          }
        }
      },
    );

    test('tombamentos numericamente diferentes nunca são equivalentes', () {
      expect(tombamentosSaoEquivalentes('123456', '123457'), isFalse);
    });

    test('dois valores vazios NUNCA são equivalentes entre si', () {
      expect(tombamentosSaoEquivalentes(null, null), isFalse);
      expect(tombamentosSaoEquivalentes('', ''), isFalse);
      expect(tombamentosSaoEquivalentes(null, ''), isFalse);
    });

    test(
      'dois valores só-zeros NUNCA são equivalentes entre si (nem com "0")',
      () {
        expect(tombamentosSaoEquivalentes('0000', '0000'), isFalse);
        expect(tombamentosSaoEquivalentes('0', '00'), isFalse);
      },
    );

    test('vazio nunca é equivalente a um numérico válido', () {
      expect(tombamentosSaoEquivalentes('', '123456'), isFalse);
      expect(tombamentosSaoEquivalentes('0000', '123456'), isFalse);
    });

    test(
      'BUG REAL: diferentes registros com o mesmo tombamento normalizado geram conflito — '
      'a função só informa equivalência; quem concilia decide que isso é CONFLITO, não fusão automática',
      () {
        // "000123456" (patrimônio A) e "123456" (patrimônio B, tombamento
        // diferente em dígitos mas idêntico depois de remover zeros) --
        // são EQUIVALENTES para fins de comparação, o que é exatamente o
        // sinal que o motor de conciliação usa para classificar como
        // CONFLITO quando pertencem a dois patrimônios distintos.
        expect(tombamentosSaoEquivalentes('000123456', '123456'), isTrue);
      },
    );

    test('não numéricos equivalentes ignoram maiúsculas/minúsculas', () {
      expect(tombamentosSaoEquivalentes('ti-769', 'TI-769'), isTrue);
    });

    test(
      'numérico nunca é equivalente a não numérico mesmo com dígitos iguais',
      () {
        expect(tombamentosSaoEquivalentes('123456', 'TI-123456'), isFalse);
      },
    );
  });
}
