import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/domain/signup_validators.dart';

void main() {
  group('validarNome', () {
    test('nome vazio é inválido', () {
      expect(validarNome(''), isNotNull);
      expect(validarNome('   '), isNotNull);
      expect(validarNome(null), isNotNull);
    });

    test('nome preenchido é válido', () {
      expect(validarNome('Fulano de Tal'), isNull);
    });
  });

  group('validarEmail', () {
    test('vazio é inválido', () {
      expect(validarEmail(''), isNotNull);
    });

    test('sem @ ou sem domínio com ponto é inválido', () {
      expect(validarEmail('fulano'), isNotNull);
      expect(validarEmail('fulano@dominio'), isNotNull);
      expect(validarEmail('fulano@dominio.'), isNotNull);
    });

    test('formato válido', () {
      expect(validarEmail('fulano@invtec.com'), isNull);
    });
  });

  group('validarCpf', () {
    test('vazio é inválido', () {
      expect(validarCpf(''), isNotNull);
      expect(validarCpf(null), isNotNull);
    });

    test('sequência repetida é inválida (mesmo com formato correto)', () {
      expect(validarCpf('11111111111'), isNotNull);
      expect(validarCpf('00000000000'), isNotNull);
    });

    test('dígito verificador incorreto é inválido', () {
      expect(validarCpf('52998224700'), isNotNull);
    });

    test('CPF válido (com e sem máscara) é aceito', () {
      expect(validarCpf('52998224725'), isNull);
      expect(validarCpf('529.982.247-25'), isNull);
    });

    test('menos de 11 dígitos é inválido', () {
      expect(validarCpf('123456789'), isNotNull);
    });
  });

  group('avaliarRequisitosSenha', () {
    test('senha vazia não satisfaz nenhum requisito', () {
      expect(avaliarRequisitosSenha(''), isEmpty);
    });

    test('cada requisito é avaliado independentemente', () {
      // só minúsculas e comprimento, falta maiúscula/número/especial
      final satisfeitos = avaliarRequisitosSenha('abcdefghijkl');
      expect(satisfeitos, contains(RequisitoSenha.comprimentoMinimo));
      expect(satisfeitos, contains(RequisitoSenha.letraMinuscula));
      expect(satisfeitos, isNot(contains(RequisitoSenha.letraMaiuscula)));
      expect(satisfeitos, isNot(contains(RequisitoSenha.numero)));
      expect(satisfeitos, isNot(contains(RequisitoSenha.caractereEspecial)));
    });

    test('senha forte satisfaz todos os 5 requisitos', () {
      final satisfeitos = avaliarRequisitosSenha('Abcdefghij1!');
      expect(satisfeitos.length, RequisitoSenha.values.length);
    });
  });

  group('validarSenha', () {
    test('vazia é inválida', () {
      expect(validarSenha(''), isNotNull);
      expect(validarSenha(null), isNotNull);
    });

    test('faltando maiúscula é inválida', () {
      expect(validarSenha('abcdefghij1!'), isNotNull);
    });

    test('faltando minúscula é inválida', () {
      expect(validarSenha('ABCDEFGHIJ1!'), isNotNull);
    });

    test('faltando número é inválida', () {
      expect(validarSenha('Abcdefghijk!'), isNotNull);
    });

    test('faltando caractere especial é inválida', () {
      expect(validarSenha('Abcdefghij12'), isNotNull);
    });

    test('menos de 12 caracteres é inválida mesmo com os outros requisitos', () {
      expect(validarSenha('Abc1!'), isNotNull);
    });

    test('satisfazendo os 5 requisitos é válida', () {
      expect(validarSenha('Abcdefghij1!'), isNull);
    });
  });

  group('validarConfirmacaoSenha', () {
    test('confirmação vazia é inválida', () {
      expect(validarConfirmacaoSenha('Abcdefghij1!', ''), isNotNull);
      expect(validarConfirmacaoSenha('Abcdefghij1!', null), isNotNull);
    });

    test('confirmação diferente é inválida', () {
      expect(validarConfirmacaoSenha('Abcdefghij1!', 'Abcdefghij1?'), isNotNull);
    });

    test('confirmação idêntica é válida', () {
      expect(validarConfirmacaoSenha('Abcdefghij1!', 'Abcdefghij1!'), isNull);
    });
  });
}
