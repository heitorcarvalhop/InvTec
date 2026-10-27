// Testes de QA focados em escala e resiliencia da importacao em lote
// (secao "cadastrarLote"/idempotencia): retomada apos interrupcao,
// idempotencia por operacaoId, isolamento de estado entre cargas de
// unidades diferentes, erros de rede isolados numa linha e volume de
// milhares de registros. Deliberadamente um arquivo NOVO, independente de
// patrimonio_import_controller_test.dart - evita conflito com outras
// frentes trabalhando nos mesmos arquivos de producao/teste ao mesmo
// tempo. Siglas de setor usadas aqui sao todas ficticias.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_lote_persistencia.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_report_export.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

Uint8List _csv(String conteudo) => Uint8List.fromList(utf8.encode(conteudo));

ImportRow _linhaParaCadastro({
  required int numeroLinha,
  required String numeroPatrimonio,
  required String operacaoId,
  String tipoId = 'tipo-fake',
  String destinoId = 'setor-fake',
}) {
  final linha = ImportRow(numeroLinha: numeroLinha, celulas: const {});
  linha.numeroPatrimonio = numeroPatrimonio;
  linha.numeroPatrimonioNormalizado = numeroPatrimonio;
  linha.tipoIdResolvido = tipoId;
  linha.destinoIdResolvido = destinoId;
  linha.status = ImportRowStatus.pronto;
  linha.operacaoId = operacaoId;
  return linha;
}

ImportRow _linhaComResultado({
  required int numeroLinha,
  required String numeroPatrimonio,
  required bool sucesso,
  String? patrimonioId,
  String? mensagemErro,
}) {
  final linha = ImportRow(numeroLinha: numeroLinha, celulas: const {});
  linha.numeroPatrimonio = numeroPatrimonio;
  linha.resultado = ImportRowResult(sucesso: sucesso, patrimonioId: patrimonioId, mensagemErro: mensagemErro);
  return linha;
}

Future<void> _processarLinhaNova(
  PatrimonioRepository repositorio,
  ImportRow linha, {
  required String loteId,
}) async {
  try {
    final resultado = await repositorio.cadastrarLote(
      tipoId: linha.tipoIdResolvido!,
      destinoId: linha.destinoIdResolvido!,
      operacaoId: linha.operacaoId!,
      loteId: loteId,
      numeroPatrimonio: linha.numeroPatrimonio,
      origemLinha: linha.numeroLinha,
    );
    linha.resultado = ImportRowResult(sucesso: true, patrimonioId: resultado.patrimonio.id);
  } catch (e) {
    linha.resultado = ImportRowResult(sucesso: false, mensagemErro: e.toString());
  }
}

Future<void> _processarLote(
  PatrimonioRepository repositorio,
  List<ImportRow> linhas, {
  required String loteId,
}) async {
  for (final linha in linhas) {
    await _processarLinhaNova(repositorio, linha, loteId: loteId);
  }
}

final _tiposMultiUnidade = [
  TipoPatrimonio(id: 'tipo-notebook-mu', nome: 'Notebook', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];

final _setoresMultiUnidade = [
  Setor(id: 'setor-origem-mu', nome: 'ORIGEM-FAKE-MU', sigla: 'OFM', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-unidade-alfa', nome: 'UNIDADE-FAKE-ALFA', sigla: 'UFA', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-unidade-beta', nome: 'UNIDADE-FAKE-BETA', sigla: 'UFB', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];

ProviderContainer _criarContainerMultiUnidade(PatrimonioRepository repositorio) {
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      tipoPatrimonioRepositoryProvider.overrideWithValue(
        FakeTipoPatrimonioRepository(tipos: _tiposMultiUnidade),
      ),
      setorRepositoryProvider.overrideWithValue(
        FakeSetorRepository(setores: _setoresMultiUnidade),
      ),
      localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
      // Este arquivo testa especificamente o caminho em LOTE
      // (`cadastrarLote`/`operacaoId`) — GATE OBRIGATÓRIO
      // (`EnvConfig.importacaoLoteExecucaoHabilitada`) desligado por
      // padrão em produção, ligado aqui só para exercitar o caminho em
      // teste (mesmo padrão de `patrimonio_import_controller_test.dart`).
      patrimonioImportControllerProvider.overrideWith(
        () => PatrimonioImportController(
          importacaoLoteExecucaoHabilitada: () => true,
          fileSystem: MemoryFileSystem(),
          resolverDiretorioPersistencia: () async => '/import-test-multi-unidade',
        ),
      ),
    ],
  );
  container.listen(patrimonioImportControllerProvider, (_, _) {});
  return container;
}

Future<void> _avancarAteRevisaoMultiUnidade(
  PatrimonioImportController controller, {
  required Uint8List bytes,
}) async {
  await controller.carregarArquivo(nomeArquivo: 'carga-unidade.csv', bytes: bytes);
  controller.confirmarCabecalho();
  controller.definirColuna(ImportColumnField.numeroPatrimonio, 0);
  controller.definirColuna(ImportColumnField.tipo, 1);
  controller.definirColuna(ImportColumnField.marca, 2);
  controller.definirColuna(ImportColumnField.numeroSerie, 3);
  controller.definirColuna(ImportColumnField.setor, 4);
  controller.avancarParaPadroes();
  controller.definirPadroes(const ImportDefaults(origemPadraoId: 'setor-origem-mu'));
  await controller.analisar();
}

void main() {
  group('Retomada apos interrupcao', () {
    test(
      'erro de rede numa linha do meio do lote: retomada (via sessao persistida) reenvia so quem nao teve sucesso',
      () async {
        const usuarioId = 'user-resiliencia-1';
        const loteId = 'lote-resiliencia-1';

        final falhasDeRedeSemEscrita = {'op-3'};
        final repo = FakePatrimonioRepository(
          operacaoIdsCadastroLoteComFalhaDeRedeSemEscrita: falhasDeRedeSemEscrita,
        );

        final linhas = [
          _linhaParaCadastro(numeroLinha: 1, numeroPatrimonio: '910001', operacaoId: 'op-1'),
          _linhaParaCadastro(numeroLinha: 2, numeroPatrimonio: '910002', operacaoId: 'op-2'),
          _linhaParaCadastro(numeroLinha: 3, numeroPatrimonio: '910003', operacaoId: 'op-3'),
          _linhaParaCadastro(numeroLinha: 4, numeroPatrimonio: '910004', operacaoId: 'op-4'),
          _linhaParaCadastro(numeroLinha: 5, numeroPatrimonio: '910005', operacaoId: 'op-5'),
        ];

        await _processarLote(repo, linhas, loteId: loteId);

        expect(linhas[0].resultado?.sucesso, isTrue);
        expect(linhas[1].resultado?.sucesso, isTrue);
        expect(linhas[2].resultado?.sucesso, isFalse);
        expect(linhas[3].resultado?.sucesso, isTrue);
        expect(linhas[4].resultado?.sucesso, isTrue);
        expect(repo.cadastrarLoteCallCount, 5);

        // mesmo "disco" (MemoryFileSystem) para as duas pontas: salvar
        // simula o fim da rodada original; carregar, de uma NOVA instância
        // de `ImportLotePersistencia`, simula o processo reaberto depois da
        // interrupção.
        final discoSimulado = MemoryFileSystem();
        const diretorio = '/import-lotes';
        await ImportLotePersistencia(diretorio, fileSystem: discoSimulado).salvar(
          ImportLoteSessaoPersistida(
            loteId: loteId,
            usuarioId: usuarioId,
            nomeArquivo: 'inventario-fake.csv',
            criadoEm: DateTime.now(),
            linhas: [
              for (final l in linhas)
                ImportLoteLinhaPersistida(
                  numeroLinha: l.numeroLinha,
                  operacaoId: l.operacaoId!,
                  status: l.resultado!.sucesso
                      ? ImportLoteLinhaPersistidaStatus.sucesso
                      : ImportLoteLinhaPersistidaStatus.falha,
                ),
            ],
          ),
        );

        final sessaoCarregada = ImportLotePersistencia(
          diretorio,
          fileSystem: discoSimulado,
        ).carregar(usuarioId);
        expect(sessaoCarregada, isNotNull);

        final jaComSucesso = sessaoCarregada!.linhas
            .where((l) => l.status == ImportLoteLinhaPersistidaStatus.sucesso)
            .map((l) => l.numeroLinha)
            .toSet();
        expect(jaComSucesso, {1, 2, 4, 5});

        final aReenviar = linhas.where((l) => !jaComSucesso.contains(l.numeroLinha)).toList();
        expect(aReenviar.map((l) => l.numeroLinha), [3]);

        falhasDeRedeSemEscrita.remove('op-3');
        for (final l in aReenviar) {
          l.resultado = null;
        }
        await _processarLote(repo, aReenviar, loteId: loteId);

        expect(linhas[2].resultado?.sucesso, isTrue);
        expect(repo.cadastrarLoteCallCount, 6);

        final encontrados910003 = await repo.buscarPorNumerosPatrimonio(['910003']);
        expect(encontrados910003, hasLength(1));
      },
    );
  });

  group('Importacao repetida / idempotencia', () {
    test('reenviar a mesma linha (mesmo operacaoId) duas vezes nunca duplica nem e tratado como erro', () async {
      final repo = FakePatrimonioRepository();

      final primeiro = await repo.cadastrarLote(
        tipoId: 'tipo-fake',
        destinoId: 'setor-fake',
        operacaoId: 'op-idem-1',
        loteId: 'lote-idem',
        numeroPatrimonio: '920001',
      );
      expect(primeiro.jaExecutado, isFalse);

      final segundo = await repo.cadastrarLote(
        tipoId: 'tipo-fake',
        destinoId: 'setor-fake',
        operacaoId: 'op-idem-1',
        loteId: 'lote-idem',
        numeroPatrimonio: '920001',
      );
      expect(segundo.jaExecutado, isTrue);
      expect(segundo.patrimonio.id, primeiro.patrimonio.id);

      expect(repo.cadastrarLoteCallCount, 2);
      final encontrados = await repo.buscarPorNumerosPatrimonio(['920001']);
      expect(encontrados, hasLength(1));
    });

    test(
      'resposta perdida (escrita efetivada mas a chamada lancou): retry com o mesmo operacaoId '
      'encontra jaExecutado, sem nova escrita',
      () async {
        final repo = FakePatrimonioRepository(
          operacaoIdsCadastroLoteComRespostaPerdida: {'op-idem-2'},
        );

        Object? erroCapturado;
        try {
          await repo.cadastrarLote(
            tipoId: 'tipo-fake',
            destinoId: 'setor-fake',
            operacaoId: 'op-idem-2',
            loteId: 'lote-idem',
            numeroPatrimonio: '920002',
          );
        } catch (e) {
          erroCapturado = e;
        }
        expect(erroCapturado, isNotNull);

        final retry = await repo.cadastrarLote(
          tipoId: 'tipo-fake',
          destinoId: 'setor-fake',
          operacaoId: 'op-idem-2',
          loteId: 'lote-idem',
          numeroPatrimonio: '920002',
        );
        expect(retry.jaExecutado, isTrue);

        final encontrados = await repo.buscarPorNumerosPatrimonio(['920002']);
        expect(encontrados, hasLength(1));
      },
    );
  });

  group('Multiplas unidades em sequencia nao compartilham estado', () {
    test('mapeamentoLocalizacoes, progresso e loteId de uma carga nunca vazam para a proxima', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainerMultiUnidade(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csvAlfa =
          'Patrimonio;Tipo;Marca;Serial;Setor\n'
          '940101;Notebook;Dell;SN-ALFA-1;UNIDADE-FAKE-ALFA\n';
      await _avancarAteRevisaoMultiUnidade(controller, bytes: _csv(csvAlfa));
      controller.definirMapeamentoLocalizacao('sala-alfa', 'loc-alfa');

      await controller.confirmarImportacao();
      final estadoAlfa = container.read(patrimonioImportControllerProvider);

      expect(estadoAlfa.mapeamentoLocalizacoes, {'sala-alfa': 'loc-alfa'});
      expect(estadoAlfa.loteIdAtual, isNotNull);
      expect(estadoAlfa.progressoAtual, 1);
      expect(estadoAlfa.progressoTotal, 1);
      final loteIdAlfa = estadoAlfa.loteIdAtual;
      expect(repo.ultimoCadastroLote?['destinoId'], 'setor-unidade-alfa');

      const csvBeta =
          'Patrimonio;Tipo;Marca;Serial;Setor\n'
          '940202;Notebook;Dell;SN-BETA-1;UNIDADE-FAKE-BETA\n';
      await _avancarAteRevisaoMultiUnidade(controller, bytes: _csv(csvBeta));
      final estadoBetaPreImportacao = container.read(patrimonioImportControllerProvider);

      expect(estadoBetaPreImportacao.mapeamentoLocalizacoes, isEmpty);
      expect(estadoBetaPreImportacao.loteIdAtual, isNull);
      expect(estadoBetaPreImportacao.progressoAtual, 0);
      expect(estadoBetaPreImportacao.progressoTotal, 0);
      expect(estadoBetaPreImportacao.linhas, hasLength(1));
      expect(estadoBetaPreImportacao.linhas.single.numeroPatrimonio, contains('940202'));

      controller.definirMapeamentoLocalizacao('sala-beta', 'loc-beta');
      await controller.confirmarImportacao();
      final estadoBeta = container.read(patrimonioImportControllerProvider);

      expect(estadoBeta.loteIdAtual, isNotNull);
      expect(estadoBeta.loteIdAtual, isNot(loteIdAlfa));
      expect(estadoBeta.mapeamentoLocalizacoes, {'sala-beta': 'loc-beta'});
      expect(repo.ultimoCadastroLote?['destinoId'], 'setor-unidade-beta');
    });
  });

  group('Erros de rede isolados numa linha do meio do lote', () {
    test(
      'erro de rede numa linha nunca e silenciosamente sucesso nem some, e as linhas seguintes continuam',
      () async {
        final repo = FakePatrimonioRepository(
          operacaoIdsCadastroLoteComFalhaDeRedeSemEscrita: {'op-rede-3'},
        );
        final linhas = [
          _linhaParaCadastro(numeroLinha: 1, numeroPatrimonio: '930001', operacaoId: 'op-rede-1'),
          _linhaParaCadastro(numeroLinha: 2, numeroPatrimonio: '930002', operacaoId: 'op-rede-2'),
          _linhaParaCadastro(numeroLinha: 3, numeroPatrimonio: '930003', operacaoId: 'op-rede-3'),
          _linhaParaCadastro(numeroLinha: 4, numeroPatrimonio: '930004', operacaoId: 'op-rede-4'),
          _linhaParaCadastro(numeroLinha: 5, numeroPatrimonio: '930005', operacaoId: 'op-rede-5'),
        ];

        await _processarLote(repo, linhas, loteId: 'lote-rede');

        expect(linhas[0].resultado?.sucesso, isTrue);
        expect(linhas[1].resultado?.sucesso, isTrue);
        expect(linhas[2].resultado, isNotNull);
        expect(linhas[2].resultado?.sucesso, isFalse);
        expect(linhas[2].resultado?.mensagemErro, isNotNull);
        expect(linhas[3].resultado?.sucesso, isTrue);
        expect(linhas[4].resultado?.sucesso, isTrue);
        expect(repo.cadastrarLoteCallCount, 5);

        final falhas = linhas.where((l) => l.resultado?.sucesso == false).toList();
        expect(falhas.map((l) => l.numeroLinha), [3]);
      },
    );
  });

  group('Lotes de milhares de registros - persistencia de progresso e relatorio', () {
    test('persistencia de progresso de 3000 linhas conclui em tempo razoavel e sem perda de dados', () async {
      const total = 3000;
      final linhasPersistidas = [
        for (var i = 1; i <= total; i++)
          ImportLoteLinhaPersistida(
            numeroLinha: i,
            operacaoId: 'op-escala-$i',
            status: i % 7 == 0 ? ImportLoteLinhaPersistidaStatus.falha : ImportLoteLinhaPersistidaStatus.sucesso,
          ),
      ];
      final sessao = ImportLoteSessaoPersistida(
        loteId: 'lote-escala',
        usuarioId: 'user-escala',
        nomeArquivo: 'carga-escala.csv',
        criadoEm: DateTime(2026, 1, 1),
        linhas: linhasPersistidas,
      );

      final persistencia = ImportLotePersistencia('/import-lotes', fileSystem: MemoryFileSystem());

      final cronometro = Stopwatch()..start();
      await persistencia.salvar(sessao);
      final carregada = persistencia.carregar('user-escala');
      cronometro.stop();
      // ignore: avoid_print
      print('[escala] ImportLotePersistencia salvar+carregar $total linhas: ${cronometro.elapsedMilliseconds}ms');

      expect(carregada, isNotNull);
      expect(carregada!.linhas, hasLength(total));
      expect(carregada.linhas.first.numeroLinha, 1);
      expect(carregada.linhas.last.numeroLinha, total);
      expect(carregada.linhas[6].status, ImportLoteLinhaPersistidaStatus.falha);
      expect(carregada.linhas[6].operacaoId, 'op-escala-7');

      expect(cronometro.elapsedMilliseconds, lessThan(5000));
    });

    test('relatorio CSV de 3000 linhas nao trunca nem corrompe dados, em tempo razoavel', () async {
      const total = 3000;
      final linhas = [
        for (var i = 1; i <= total; i++)
          _linhaComResultado(
            numeroLinha: i,
            numeroPatrimonio: '95${i.toString().padLeft(5, '0')}',
            sucesso: i % 11 != 0,
            patrimonioId: i % 11 != 0 ? 'pat-$i' : null,
            mensagemErro: i % 11 == 0 ? 'Falha simulada na linha $i' : null,
          ),
      ];

      final cronometro = Stopwatch()..start();
      final relatorio = ImportReport.fromImportRows(
        loteId: 'lote-escala-csv',
        nomeArquivo: 'carga.csv',
        linhas: linhas,
      );
      final bytes = gerarCsvRelatorioImportacao(relatorio.linhas);
      cronometro.stop();
      // ignore: avoid_print
      print('[escala] gerarCsvRelatorioImportacao $total linhas: ${cronometro.elapsedMilliseconds}ms');

      final texto = utf8.decode(bytes);
      final linhasCsv = texto.split('\r\n').where((l) => l.isNotEmpty).toList();
      expect(linhasCsv, hasLength(total + 1));
      expect(linhasCsv[1], startsWith('1,9500001,Sucesso,pat-1,'));
      expect(linhasCsv[total], startsWith('$total,'));

      final ultimaLinhaFalha = (total ~/ 11) * 11;
      expect(linhasCsv[ultimaLinhaFalha], contains('Falha simulada na linha $ultimaLinhaFalha'));

      expect(cronometro.elapsedMilliseconds, lessThan(5000));

      final persistenciaRelatorio = ImportReportPersistencia('/import-relatorios', fileSystem: MemoryFileSystem());
      await persistenciaRelatorio.salvar(relatorio);
      final carregado = persistenciaRelatorio.carregar('lote-escala-csv');
      expect(carregado, isNotNull);
      expect(carregado!.linhas, hasLength(total));
    });
  });
}
