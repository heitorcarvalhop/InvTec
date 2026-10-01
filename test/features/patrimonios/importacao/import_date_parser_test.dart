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

    test('retorna null quando ano de 2 dígitos resultaria em data futura', () {
      // "98" sempre vira 20xx (regra acima) — sem faixa de sanidade isso
      // geraria uma data de aquisição no futuro (2098) sem nenhum aviso.
      expect(interpretarDataTexto('10/03/98'), isNull);
    });

    test('retorna null para data futura com ano de 4 dígitos', () {
      expect(interpretarDataTexto('10/03/2099'), isNull);
    });

    test('retorna null para data anterior a 2000', () {
      expect(interpretarDataTexto('10/03/1999'), isNull);
    });

    test('aceita a data de hoje', () {
      final hoje = DateTime.now();
      final texto =
          '${hoje.day.toString().padLeft(2, '0')}/${hoje.month.toString().padLeft(2, '0')}/${hoje.year}';
      expect(interpretarDataTexto(texto), DateTime(hoje.year, hoje.month, hoje.day));
    });
  });
}
