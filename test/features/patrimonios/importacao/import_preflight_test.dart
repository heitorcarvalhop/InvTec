import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_preflight.dart';
import 'package:invtec/features/setores/domain/setor.dart';

Setor _setor({required String sigla, required bool ativo}) => Setor(
  id: 'setor-$sigla-$ativo-${identityHashCode(sigla)}',
  nome: 'Setor $sigla',
  sigla: sigla,
  ativo: ativo,
  criadoEm: DateTime(2026, 1, 1),
);

void main() {
  group('ImportPreflight.validarGerenciaUnica (PROMPT 8.10)', () {
    test('exatamente uma gerência com a sigla, ativa: ok', () {
      final resultado = ImportPreflight.validarGerenciaUnica(
        setores: [_setor(sigla: 'GETEC', ativo: true), _setor(sigla: 'TI', ativo: true)],
        sigla: 'GETEC',
      );
      expect(resultado.ok, isTrue);
      expect(resultado.issues, isEmpty);
    });

    test('nenhuma gerência com a sigla: bloqueia o preflight', () {
      final resultado = ImportPreflight.validarGerenciaUnica(
        setores: [_setor(sigla: 'TI', ativo: true)],
        sigla: 'GETEC',
      );
      expect(resultado.ok, isFalse);
      expect(resultado.issues, hasLength(1));
      expect(resultado.issues.single.mensagem, contains('Nenhuma gerência'));
    });

    test('gerência com a sigla existe mas está inativa: bloqueia o preflight', () {
      final resultado = ImportPreflight.validarGerenciaUnica(
        setores: [_setor(sigla: 'GETEC', ativo: false)],
        sigla: 'GETEC',
      );
      expect(resultado.ok, isFalse);
      expect(resultado.issues.single.mensagem, contains('inativa'));
    });

    test('mais de uma gerência com a mesma sigla: ambiguidade bloqueia o preflight', () {
      final resultado = ImportPreflight.validarGerenciaUnica(
        setores: [_setor(sigla: 'GETEC', ativo: true), _setor(sigla: 'GETEC', ativo: true)],
        sigla: 'GETEC',
      );
      expect(resultado.ok, isFalse);
      expect(resultado.issues.single.mensagem, contains('Encontradas 2'));
    });
  });

  group('ImportPreflight.validarNomesEsperados (PROMPT 8.10)', () {
    test('todos os nomes esperados presentes (com variação de caixa/espaço): ok', () {
      final resultado = ImportPreflight.validarNomesEsperados(
        nomesEncontrados: ['getec - universitário', '  Home Office  ', 'Situação/Situada - PA'],
        nomesEsperados: ['GETEC - Universitário', 'Home Office', 'SITUAÇÃO/SITUADA - PA'],
      );
      expect(resultado.ok, isTrue);
      expect(resultado.issues, isEmpty);
    });

    test('catálogo real incompleto (um nome esperado ausente): bloqueia o preflight', () {
      final resultado = ImportPreflight.validarNomesEsperados(
        nomesEncontrados: ['GETEC - Universitário', 'Home Office'],
        nomesEsperados: ['GETEC - Universitário', 'Home Office', 'GETEC - Canidé'],
      );
      expect(resultado.ok, isFalse);
      expect(resultado.issues, hasLength(1));
      expect(resultado.issues.single.mensagem, contains('GETEC - Canidé'));
    });

    test('nomes extras no catálogo real não são um problema', () {
      final resultado = ImportPreflight.validarNomesEsperados(
        nomesEncontrados: ['GETEC - Universitário', 'Localização Nova Que Não Estava No Mapeamento'],
        nomesEsperados: ['GETEC - Universitário'],
      );
      expect(resultado.ok, isTrue);
    });

    test('mais de um nome esperado ausente: reporta todos, nunca só o primeiro', () {
      final resultado = ImportPreflight.validarNomesEsperados(
        nomesEncontrados: const [],
        nomesEsperados: ['A', 'B', 'C'],
      );
      expect(resultado.ok, isFalse);
      expect(resultado.issues, hasLength(3));
    });
  });
}
