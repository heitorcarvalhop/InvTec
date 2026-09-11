import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_date_parser.dart';

void main() {
  group('interpretarDataTexto', () {
    test('aceita dd/mm/yyyy', () {
      expect(interpretarDataTexto('10/03/2024'), DateTime(2024, 3, 10));
    });

    test('aceita yyyy-mm-dd (ISO)', () {
      expect(interpretarDataTexto('2024-03-10'), DateTime(2024, 3, 10));
    });

    test('aceita dd-mm-yyyy', () {
      expect(interpretarDataTexto('10-03-2024'), DateTime(2024, 3, 10));
    });

    test('aceita ano com 2 dígitos', () {
      expect(interpretarDataTexto('10/03/24'), DateTime(2024, 3, 10));
    });

    test('retorna null para data inválida (dia 31 de fevereiro)', () {
      expect(interpretarDataTexto('31/02/2024'), isNull);
    });

    test('retorna null para texto que não é data', () {
      expect(interpretarDataTexto('não é uma data'), isNull);
    });

    test('retorna null para texto vazio', () {
      expect(interpretarDataTexto(''), isNull);
      expect(interpretarDataTexto('   '), isNull);
    });
  });
}
