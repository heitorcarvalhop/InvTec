import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// PROMPT 8.14: testes da revisão final como barreira de segurança — a
/// pergunta "e se eu importar outra planilha repetida?" (seção 10), a
/// corrida entre análise e confirmação (seção 11), e a prova de zero N+1
/// (seção 8). Nenhum destes testes chama `confirmarImportacao()` — a
/// própria importação continua fora do escopo (só a barreira é validada).
final _tipos = [
  TipoPatrimonio(id: 'tipo-notebook', nome: 'Notebook', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
final _setores = [
  Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-almoxarifado', nome: 'Almoxarifado', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
const _localizacoes = <Localizacao>[];

ProviderContainer _criarContainer(PatrimonioRepository repositorio) {
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
      setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
      localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: _localizacoes)),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
    ],
  );
  container.listen(patrimonioImportControllerProvider, (_, _) {});
  return container;
}

Uint8List _csv(String conteudo) => Uint8List.fromList(utf8.encode(conteudo));

Future<void> _avancarAteRevisao(PatrimonioImportController controller, {required Uint8List bytes}) async {
  await controller.carregarArquivo(nomeArquivo: 'inventario.csv', bytes: bytes);
  controller.confirmarCabecalho();
  controller.definirColuna(ImportColumnField.numeroPatrimonio, 0);
  controller.definirColuna(ImportColumnField.tipo, 1);
  controller.definirColuna(ImportColumnField.marca, 2);
  controller.definirColuna(ImportColumnField.numeroSerie, 3);
  controller.definirColuna(ImportColumnField.setor, 4);
  controller.avancarParaPadroes();
  controller.definirPadroes(const ImportDefaults(origemPadraoId: 'setor-almoxarifado'));
  await controller.analisar();
}

PatrimonioDetalhe _existente(String numero) => PatrimonioDetalhe(
  patrimonio: Patrimonio(
    id: 'existente-$numero',
    numeroPatrimonio: numero,
    tipoId: 'tipo-notebook',
    status: PatrimonioStatus.disponivel,
    setorAtualId: 'setor-getec',
    dataCadastro: DateTime(2025, 1, 1),
    atualizadoEm: DateTime(2025, 1, 1),
  ),
  tipoNome: 'Notebook',
  setorNome: 'GETEC',
);

void main() {
  group('PROMPT 8.14 — cenário A: arquivo repetido depois de uma importação anterior', () {
    test('números já cadastrados aparecem como já existentes; só o número novo é enviado', () async {
      final repo = FakePatrimonioRepository(itens: [_existente('100'), _existente('101'), _existente('102')]);
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n'
          '100;Notebook;Dell;S100;GETEC\n'
          '101;Notebook;Dell;S101;GETEC\n'
          '102;Notebook;Dell;S102;GETEC\n'
          '103;Notebook;Dell;S103;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final resumo = container.read(patrimonioImportControllerProvider).resumo;
      expect(resumo.total, 4);
      expect(resumo.existentes, 3);
      expect(resumo.novos, 1);
      expect(resumo.totalParaEnviar, 1);

      final novo = container.read(patrimonioImportControllerProvider).linhas.firstWhere(
            (l) => l.numeroPatrimonio == '103',
          );
      expect(novo.status, ImportRowStatus.pronto);
      expect(novo.seraEnviada, isTrue);

      for (final numero in ['100', '101', '102']) {
        final linha = container.read(patrimonioImportControllerProvider).linhas.firstWhere(
              (l) => l.numeroPatrimonio == numero,
            );
        expect(linha.status, ImportRowStatus.existente);
        expect(linha.seraEnviada, isFalse);
      }
    });
  });

  group('PROMPT 8.14 — cenário B: duplicado no próprio arquivo', () {
    test('as duas ocorrências ficam DUPLICADO NO ARQUIVO; o número sem conflito é enviado normalmente', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n'
          '200;Notebook;Dell;S1;GETEC\n'
          '200;Notebook;HP;S2;GETEC\n'
          '201;Notebook;Dell;S3;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final resumo = container.read(patrimonioImportControllerProvider).resumo;
      expect(resumo.duplicados, 2);
      expect(resumo.novos, 1);
      expect(resumo.totalParaEnviar, 1);

      final linhas200 = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .where((l) => l.numeroPatrimonio == '200')
          .toList();
      expect(linhas200, hasLength(2));
      expect(linhas200.every((l) => l.duplicadoNoArquivo && l.status == ImportRowStatus.erro), isTrue);
      // o sistema nunca escolhe sozinho qual "200" usar.
      expect(linhas200.every((l) => l.seraEnviada), isFalse);

      final linha201 = container.read(patrimonioImportControllerProvider).linhas.firstWhere(
            (l) => l.numeroPatrimonio == '201',
          );
      expect(linha201.status, ImportRowStatus.pronto);
    });
  });

  group('PROMPT 8.14 — cenário C: serial repetido entre dois patrimônios diferentes', () {
    test('gera aviso em cada linha, nunca erro, e ambas continuam enviáveis', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n'
          '300;Notebook;Dell;ABC;GETEC\n'
          '301;Notebook;Microsoft;ABC;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final resumo = container.read(patrimonioImportControllerProvider).resumo;
      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      expect(linhas.every((l) => l.possivelDuplicidadeSerial), isTrue);
      expect(linhas.every((l) => l.status == ImportRowStatus.aviso), isTrue);
      expect(linhas.every((l) => l.seraEnviada), isTrue);
      expect(
        linhas.every((l) => l.issues.any((i) => i.message.contains('não impede a importação'))),
        isTrue,
      );
      expect(resumo.erros, 0);
      expect(resumo.novos, 2);
      expect(resumo.avisos, 2);
    });
  });

  group('PROMPT 8.14 — revalidação (seção 7): corrida entre análise e confirmação', () {
    test('um número que não existia na análise, mas passou a existir depois, some da lista de novos', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n500;Notebook;Dell;S500;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      var linha500 = container.read(patrimonioImportControllerProvider).linhas.firstWhere(
            (l) => l.numeroPatrimonio == '500',
          );
      expect(linha500.status, ImportRowStatus.pronto);
      expect(linha500.seraEnviada, isTrue);
      expect(container.read(patrimonioImportControllerProvider).resumo.novos, 1);

      // simula outro processo/usuário cadastrando "500" no intervalo entre a
      // análise e a confirmação — direto no repositório fake (equivalente a
      // uma escrita concorrente real, nunca feita por este teste via o
      // controller/importador).
      await repo.cadastrar(tipoId: 'tipo-notebook', destinoId: 'setor-getec', numeroPatrimonio: '500');

      await controller.revalidarAntesDeConfirmar();

      final estado = container.read(patrimonioImportControllerProvider);
      linha500 = estado.linhas.firstWhere((l) => l.numeroPatrimonio == '500');
      expect(linha500.status, ImportRowStatus.existente);
      expect(linha500.seraEnviada, isFalse);
      expect(estado.resumo.novos, 0);
      expect(estado.resumo.existentes, 1);
      expect(estado.revalidacaoNumerosQueViraramExistentes, contains('500'));
      expect(estado.revalidacaoValidaParaEstadoAtual, isTrue);

      // nunca tentou cadastrar de novo.
      expect(repo.cadastrarCallCount, 1); // só a chamada simulada acima.
    });

    test('revalidação não altera nada quando o estado do banco continua igual', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n600;Notebook;Dell;S600;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      await controller.revalidarAntesDeConfirmar();

      final estado = container.read(patrimonioImportControllerProvider);
      expect(estado.resumo.novos, 1);
      expect(estado.resumo.existentes, 0);
      expect(estado.revalidacaoNumerosQueViraramExistentes, isEmpty);
      expect(estado.revalidacaoValidaParaEstadoAtual, isTrue);
    });

    test('uma decisão manual depois da revalidação invalida a barreira até revalidar de novo', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n700;Notebook;Dell;S700;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));
      await controller.revalidarAntesDeConfirmar();
      expect(container.read(patrimonioImportControllerProvider).revalidacaoValidaParaEstadoAtual, isTrue);

      final linha = container.read(patrimonioImportControllerProvider).linhas.first;
      controller.alternarIgnorarLinha(linha, true);

      expect(container.read(patrimonioImportControllerProvider).revalidacaoValidaParaEstadoAtual, isFalse);
    });

    test('revalidação nunca chama cadastrar/atualizar — só leitura em lote', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n800;Notebook;Dell;S800;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));
      await controller.revalidarAntesDeConfirmar();

      expect(repo.cadastrarCallCount, 0);
      expect(repo.atualizarCallCount, 0);
    });
  });

  group('PROMPT 8.14 — seção 8: zero N+1 (análise + revalidação)', () {
    test('análise e revalidação juntas fazem só 2 chamadas em lote, independente do número de linhas', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      final linhasCsv = List.generate(50, (i) => '${1000 + i};Notebook;Dell;S$i;GETEC').join('\n');
      final csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n$linhasCsv\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));
      expect(repo.buscarPorNumerosPatrimonioCallCount, 1);

      await controller.revalidarAntesDeConfirmar();
      expect(repo.buscarPorNumerosPatrimonioCallCount, 2);

      expect(container.read(patrimonioImportControllerProvider).resumo.total, 50);
      expect(container.read(patrimonioImportControllerProvider).resumo.novos, 50);
    });

    test('linhas já marcadas "atualizar" não entram na revalidação (já são um existente conhecido)', () async {
      final repo = FakePatrimonioRepository(itens: [_existente('900')]);
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n900;Notebook;Dell Novo;S900;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));
      final linha = container.read(patrimonioImportControllerProvider).linhas.single;
      controller.decidirExistente(linha, ImportExistingAction.atualizarMetadados);
      expect(container.read(patrimonioImportControllerProvider).linhas.single.status, ImportRowStatus.atualizar);

      final chamadasAntes = repo.buscarPorNumerosPatrimonioCallCount;
      await controller.revalidarAntesDeConfirmar();
      // nenhuma chamada nova: não havia candidato a "novo" para revalidar.
      expect(repo.buscarPorNumerosPatrimonioCallCount, chamadasAntes);
      expect(container.read(patrimonioImportControllerProvider).linhas.single.status, ImportRowStatus.atualizar);
    });
  });
}
