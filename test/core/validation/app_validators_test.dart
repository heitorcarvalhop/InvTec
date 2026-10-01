import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/validation/app_validators.dart';

void main() {
  group('AppValidators.numeroPatrimonio', () {
    test('aceita vazio (campo opcional)', () {
      expect(AppValidators.numeroPatrimonio(null), isNull);
      expect(AppValidators.numeroPatrimonio(''), isNull);
      expect(AppValidators.numeroPatrimonio('   '), isNull);
    });

    test('aceita somente dígitos, inclusive com zeros à esquerda', () {
      expect(AppValidators.numeroPatrimonio('00045872'), isNull);
      expect(AppValidators.numeroPatrimonio('123'), isNull);
    });

    test('rejeita letras ou qualquer caractere não numérico', () {
      expect(AppValidators.numeroPatrimonio('ABC123'), isNotNull);
      expect(AppValidators.numeroPatrimonio('123-45'), isNotNull);
      expect(AppValidators.numeroPatrimonio('12 34'), isNotNull);
    });
  });

  group('AppValidators.numeroDocumentoSei', () {
    test('aceita vazio e dígitos, inclusive com zeros à esquerda', () {
      expect(AppValidators.numeroDocumentoSei(null), isNull);
      expect(AppValidators.numeroDocumentoSei(''), isNull);
      expect(AppValidators.numeroDocumentoSei('00095955192'), isNull);
    });

    test('rejeita letras', () {
      expect(AppValidators.numeroDocumentoSei('95955ABC'), isNotNull);
    });
  });

  group('AppValidators.numeroChamado', () {
    test('aceita vazio e dígitos, inclusive com zeros à esquerda', () {
      expect(AppValidators.numeroChamado(null), isNull);
      expect(AppValidators.numeroChamado(''), isNull);
      expect(AppValidators.numeroChamado('04556'), isNull);
    });

    test('rejeita letras', () {
      expect(AppValidators.numeroChamado('CH-4556'), isNotNull);
    });
  });

  group('AppValidators.email', () {
    test('rejeita vazio', () {
      expect(AppValidators.email(null), isNotNull);
      expect(AppValidators.email(''), isNotNull);
      expect(AppValidators.email('   '), isNotNull);
    });

    test('aceita formato válido', () {
      expect(AppValidators.email('usuario@getec.go.gov.br'), isNull);
      expect(AppValidators.email('  usuario@dominio.com  '), isNull);
    });

    test('rejeita texto sem @ ou sem domínio com ponto', () {
      expect(AppValidators.email('usuario'), isNotNull);
      expect(AppValidators.email('usuario@dominio'), isNotNull);
      expect(AppValidators.email('@dominio.com'), isNotNull);
      expect(AppValidators.email('usuario@dominio.'), isNotNull);
    });
  });
}
