import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/text_similarity.dart';

void main() {
  group('normalizarTextoComparacao', () {
    test('remove acentos, espaços extras e diferenças de caixa', () {
      expect(normalizarTextoComparacao('  GETEC  '), 'getec');
      expect(normalizarTextoComparacao('Núcleo   de   TI'), 'nucleo de ti');
      expect(normalizarTextoComparacao('Notebook'), normalizarTextoComparacao('NOTEBOOK'));
    });
  });

  group('distanciaLevenshtein', () {
    test('zero para strings iguais', () {
      expect(distanciaLevenshtein('notebook', 'notebook'), 0);
    });

    test('conta as edições necessárias', () {
      expect(distanciaLevenshtein('notebok', 'notebook'), 1);
      expect(distanciaLevenshtein('gtec', 'getec'), 1);
    });
  });

  group('sugerirMaisParecido', () {
    test('sugere o candidato mais próximo dentro da distância máxima', () {
      final sugestao = sugerirMaisParecido(
        valor: 'Notebok',
        candidatos: ['Notebook', 'Monitor', 'Desktop'],
        textoDe: (s) => s,
      );
      expect(sugestao, 'Notebook');
    });

    test('não sugere nada quando não há candidato próximo o bastante', () {
      final sugestao = sugerirMaisParecido(
        valor: 'Impressora',
        candidatos: ['Notebook', 'Monitor'],
        textoDe: (s) => s,
      );
      expect(sugestao, isNull);
    });
  });
}
