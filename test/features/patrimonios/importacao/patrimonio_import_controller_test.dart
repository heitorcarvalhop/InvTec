import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/patrimonios_resultado.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/getec_import_profile.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/import_profile_id.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

final _tipos = [
  TipoPatrimonio(id: 'tipo-notebook', nome: 'Notebook', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  TipoPatrimonio(id: 'tipo-software', nome: 'Software / Licença', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  TipoPatrimonio(id: 'tipo-mobiliario', nome: 'Mobiliário', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
final _setores = [
  Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GE', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-almoxarifado', nome: 'Almoxarifado', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-ti', nome: 'TI', sigla: 'TI', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];

/// Decora um [FakePatrimonioRepository] para forçar falha seletiva em
/// `cadastrar`/`atualizar` para números escolhidos pelo teste — usado para
/// simular falha parcial (seção 28) sem depender de rede real.
class _RepositorioComFalhaSeletiva implements PatrimonioRepository {
  _RepositorioComFalhaSeletiva(this._delegado);

  final FakePatrimonioRepository _delegado;
  Set<String> numerosParaFalhar = {};

  @override
  Future<Patrimonio> cadastrar({
    required String tipoId,
    required String destinoId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
  }) async {
    if (numerosParaFalhar.contains(numeroPatrimonio)) {
      throw const AppException('Falha simulada de rede.');
    }
    return _delegado.cadastrar(
      tipoId: tipoId,
      destinoId: destinoId,
      numeroPatrimonio: numeroPatrimonio,
      numeroSerie: numeroSerie,
      marca: marca,
      modelo: modelo,
      descricao: descricao,
      observacao: observacao,
      dataAquisicao: dataAquisicao,
      origemId: origemId,
      responsavelOrigem: responsavelOrigem,
      responsavelDestino: responsavelDestino,
      motivo: motivo,
      observacaoMovimentacao: observacaoMovimentacao,
      dataMovimentacao: dataMovimentacao,
    );
  }

  @override
  Future<Patrimonio> atualizar({
    required String id,
    String? numeroPatrimonio,
    String? numeroSerie,
    required String tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  }) {
    return _delegado.atualizar(
      id: id,
      numeroPatrimonio: numeroPatrimonio,
      numeroSerie: numeroSerie,
      tipoId: tipoId,
      marca: marca,
      modelo: modelo,
      descricao: descricao,
      observacao: observacao,
      dataAquisicao: dataAquisicao,
    );
  }

  @override
  Future<Patrimonio?> buscarPorId(String id) => _delegado.buscarPorId(id);

  @override
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id) => _delegado.buscarDetalhePorId(id);

  @override
  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio) =>
      _delegado.buscarPorNumeroPatrimonio(numeroPatrimonio);

  @override
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros) =>
      _delegado.buscarPorNumerosPatrimonio(numeros);

  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) =>
      _delegado.buscarNumerosSerieExistentes(numerosSerie);
}

/// Repositório que só libera cada `cadastrar` quando o teste manda — usado
/// para testar cancelamento entre lotes de forma determinística (seção 27).
class _RepositorioComPortoes implements PatrimonioRepository {
  _RepositorioComPortoes(this._delegado);

  final FakePatrimonioRepository _delegado;
  final List<Completer<void>> portoesAbertos = [];

  @override
  Future<Patrimonio> cadastrar({
    required String tipoId,
    required String destinoId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
  }) async {
    final portao = Completer<void>();
    portoesAbertos.add(portao);
    await portao.future;
    return _delegado.cadastrar(
      tipoId: tipoId,
      destinoId: destinoId,
      numeroPatrimonio: numeroPatrimonio,
      numeroSerie: numeroSerie,
      marca: marca,
      modelo: modelo,
      descricao: descricao,
      observacao: observacao,
      dataAquisicao: dataAquisicao,
      origemId: origemId,
      responsavelOrigem: responsavelOrigem,
      responsavelDestino: responsavelDestino,
      motivo: motivo,
      observacaoMovimentacao: observacaoMovimentacao,
      dataMovimentacao: dataMovimentacao,
    );
  }

  @override
  Future<Patrimonio> atualizar({
    required String id,
    String? numeroPatrimonio,
    String? numeroSerie,
    required String tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  }) =>
      _delegado.atualizar(
        id: id,
        numeroPatrimonio: numeroPatrimonio,
        numeroSerie: numeroSerie,
        tipoId: tipoId,
        marca: marca,
        modelo: modelo,
        descricao: descricao,
        observacao: observacao,
        dataAquisicao: dataAquisicao,
      );

  @override
  Future<Patrimonio?> buscarPorId(String id) => _delegado.buscarPorId(id);

  @override
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id) => _delegado.buscarDetalhePorId(id);

  @override
  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio) =>
      _delegado.buscarPorNumeroPatrimonio(numeroPatrimonio);

  @override
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros) =>
      _delegado.buscarPorNumerosPatrimonio(numeros);

  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) =>
      _delegado.buscarNumerosSerieExistentes(numerosSerie);
}

ProviderContainer _criarContainer(PatrimonioRepository repositorio) {
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
      setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
    ],
  );
  // mantém o NotifierProvider.autoDispose vivo durante todo o teste
  container.listen(patrimonioImportControllerProvider, (_, _) {});
  return container;
}

Uint8List _csv(String conteudo) => Uint8List.fromList(utf8.encode(conteudo));

/// Avança até o passo de revisão. Por padrão já configura uma origem
/// padrão válida ('setor-getec'), já que a origem é obrigatória para
/// patrimônios novos nesta importação (seção 1 da correção) — os testes
/// que não são especificamente sobre origem não devem ser derrubados por
/// essa regra; passe [padroes] explicitamente para testar o caso sem
/// origem resolvida.
Future<void> _avancarAteRevisao(
  PatrimonioImportController controller, {
  required Uint8List bytes,
  ImportDefaults? padroes,
}) async {
  await controller.carregarArquivo(nomeArquivo: 'inventario.csv', bytes: bytes);
  controller.confirmarCabecalho();
  controller.definirColuna(ImportColumnField.numeroPatrimonio, 0);
  controller.definirColuna(ImportColumnField.tipo, 1);
  controller.definirColuna(ImportColumnField.marca, 2);
  controller.definirColuna(ImportColumnField.numeroSerie, 3);
  controller.definirColuna(ImportColumnField.setor, 4);
  controller.avancarParaPadroes();
  // 'setor-almoxarifado' (distinto do destino 'GETEC' usado nos testes) para
  // não colidir com a nova regra "origem e destino precisam ser diferentes".
  controller.definirPadroes(padroes ?? const ImportDefaults(origemPadraoId: 'setor-almoxarifado'));
  await controller.analisar();
}

void main() {
  group('PatrimonioImportController — pipeline completo', () {
    test('carrega CSV, mapeia, aplica padrões e classifica as linhas', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n'
          '00045872;Notebook;Dell;AAA1;GETEC\n'
          '00045873;Notebook;Dell;AAA2;Setor Desconhecido\n';

      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.step, ImportStep.revisar);
      expect(state.linhas, hasLength(2));

      final pronta = state.linhas.firstWhere((l) => l.numeroPatrimonio == '00045872');
      expect(pronta.status, ImportRowStatus.pronto);

      final comErro = state.linhas.firstWhere((l) => l.numeroPatrimonio == '00045873');
      expect(comErro.status, ImportRowStatus.erro);
    });

    test('origem ausente e sem origem padrão bloqueia a linha com erro', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n00045872;Notebook;Dell;AAA1;GETEC\n';
      // padrões explícitos, sem origemPadraoId — não usa o default do helper.
      await _avancarAteRevisao(controller, bytes: _csv(csv), padroes: const ImportDefaults());

      final linha = container.read(patrimonioImportControllerProvider).linhas.single;
      expect(linha.status, ImportRowStatus.erro);
      expect(
        linha.issues.any((i) => i.message.contains('Nenhuma origem informada')),
        isTrue,
      );
    });

    test('linha classificada como erro nunca chega a repository.cadastrar', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n00045872;Notebook;Dell;AAA1;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv), padroes: const ImportDefaults());
      expect(container.read(patrimonioImportControllerProvider).linhas.single.status, ImportRowStatus.erro);

      await controller.confirmarImportacao();

      expect(repo.cadastrarCallCount, 0);
    });

    test('nunca importa automaticamente: revisar não dispara nenhuma gravação', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n00045872;Notebook;Dell;AAA1;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      expect(repo.cadastrarCallCount, 0);
    });

    test('detecta patrimônio já existente e não sobrescreve setor/responsável sem decisão explícita', () async {
      final existente = PatrimonioDetalhe(
        patrimonio: Patrimonio(
          id: 'existing-1',
          numeroPatrimonio: '00000001',
          tipoId: 'tipo-notebook',
          status: PatrimonioStatus.disponivel,
          setorAtualId: 'setor-getec',
          dataCadastro: DateTime(2025, 1, 1),
          atualizadoEm: DateTime(2025, 1, 1),
        ),
        tipoNome: 'Notebook',
        setorNome: 'GETEC',
      );
      final repo = FakePatrimonioRepository(itens: [existente]);
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n00000001;Notebook;Dell Novo;ZZZ;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final linha = container.read(patrimonioImportControllerProvider).linhas.single;
      expect(linha.status, ImportRowStatus.existente);

      controller.decidirExistente(linha, ImportExistingAction.atualizarMetadados);
      expect(linha.status, ImportRowStatus.atualizar);
    });
  });

  group('PatrimonioImportController — decisões manuais', () {
    test('aplicar sugestão de tipo resolve o erro e reclassifica como pronto', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n00045872;Notebok;Dell;AAA1;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final linha = container.read(patrimonioImportControllerProvider).linhas.single;
      expect(linha.status, ImportRowStatus.erro);
      expect(linha.tipoIdSugerido, 'tipo-notebook');

      controller.definirTipoDaLinha(linha, linha.tipoIdSugerido);
      expect(linha.status, ImportRowStatus.pronto);
    });

    test('duplicidade no arquivo: manter primeira ocorrência ignora as demais', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n'
          '77777;Notebook;Dell;S1;GETEC\n'
          '77777;Notebook;HP;S2;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      expect(linhas.every((l) => l.status == ImportRowStatus.erro), isTrue);

      controller.manterPrimeiraOcorrencia('77777');

      final atualizado = container.read(patrimonioImportControllerProvider).linhas;
      final mantida = atualizado.firstWhere((l) => l.marca == 'Dell');
      final ignorada = atualizado.firstWhere((l) => l.marca == 'HP');
      expect(mantida.status, ImportRowStatus.pronto);
      expect(ignorada.status, ImportRowStatus.ignorado);
    });

    test('ignorar manualmente a última linha de um grupo duplicado libera a primeira', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n'
          '88888;Notebook;Dell;S1;GETEC\n'
          '88888;Notebook;HP;S2;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      final segunda = linhas.firstWhere((l) => l.marca == 'HP');
      controller.alternarIgnorarLinha(segunda, true);

      final primeira = container.read(patrimonioImportControllerProvider).linhas.firstWhere(
            (l) => l.marca == 'Dell',
          );
      expect(primeira.duplicadoNoArquivo, isFalse);
      expect(primeira.status, ImportRowStatus.pronto);
      expect(segunda.status, ImportRowStatus.ignorado);
    });
  });

  group('PatrimonioImportController — confirmarImportacao', () {
    test('envia só linhas prontas/aviso/atualizar e nunca inclui "status" nos parâmetros', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n'
          '00045872;Notebook;Dell;AAA1;GETEC\n'
          '00045873;Notebook;Dell;AAA2;Setor Inexistente\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      await controller.confirmarImportacao();

      expect(repo.cadastrarCallCount, 1);
      expect(repo.ultimoCadastro!.containsKey('status'), isFalse);
      expect(container.read(patrimonioImportControllerProvider).step, ImportStep.resultado);
    });

    test('processa em lotes de no máximo 5 gravações simultâneas', () async {
      final delegado = FakePatrimonioRepository();
      var emAndamento = 0;
      var maximoObservado = 0;

      Future<Patrimonio> gravar(Future<Patrimonio> Function() acao) async {
        emAndamento++;
        if (emAndamento > maximoObservado) maximoObservado = emAndamento;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final resultado = await acao();
        emAndamento--;
        return resultado;
      }

      final repo = _RepositorioContadorConcorrencia(delegado, gravar);
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      final linhasCsv = List.generate(
        12,
        (i) => '${1000 + i};Notebook;Dell;S$i;GETEC',
      ).join('\n');
      final csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n$linhasCsv\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      await controller.confirmarImportacao();

      expect(delegado.cadastrarCallCount, 12);
      expect(maximoObservado, lessThanOrEqualTo(importConcorrenciaMaxima));
      expect(maximoObservado, greaterThan(1));
    });

    test('falha parcial não interrompe as demais linhas; retry reenvia só as que falharam', () async {
      final delegado = FakePatrimonioRepository();
      final repo = _RepositorioComFalhaSeletiva(delegado)..numerosParaFalhar = {'20002'};
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n'
          '20001;Notebook;Dell;S1;GETEC\n'
          '20002;Notebook;Dell;S2;GETEC\n'
          '20003;Notebook;Dell;S3;GETEC\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      await controller.confirmarImportacao();

      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      expect(linhas.where((l) => l.resultado?.sucesso == true), hasLength(2));
      expect(linhas.where((l) => l.resultado?.sucesso == false), hasLength(1));
      expect(delegado.cadastrarCallCount, 2); // a que falhou não chegou a chamar o delegado

      repo.numerosParaFalhar = {};
      await controller.tentarNovamenteFalhas();

      final linhasFinal = container.read(patrimonioImportControllerProvider).linhas;
      expect(linhasFinal.every((l) => l.resultado?.sucesso == true), isTrue);
      expect(delegado.cadastrarCallCount, 3);
    });

    test('cancelamento entre lotes preserva o que já foi importado e não processa o resto', () async {
      final delegado = FakePatrimonioRepository();
      final repo = _RepositorioComPortoes(delegado);
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      final linhasCsv = List.generate(
        7,
        (i) => '${3000 + i};Notebook;Dell;S$i;GETEC',
      ).join('\n');
      final csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n$linhasCsv\n';
      await _avancarAteRevisao(controller, bytes: _csv(csv));

      final futuro = controller.confirmarImportacao();
      // espera o primeiro lote (5) ficar bloqueado nos portões
      while (repo.portoesAbertos.length < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      controller.solicitarCancelamento();
      for (final portao in repo.portoesAbertos) {
        portao.complete();
      }
      await futuro;

      expect(delegado.cadastrarCallCount, 5);
      expect(container.read(patrimonioImportControllerProvider).cancelamentoSolicitado, isTrue);
      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      expect(linhas.where((l) => l.resultado != null), hasLength(5));
      expect(linhas.where((l) => l.resultado == null), hasLength(2));
    });
  });

  group('PatrimonioImportController — perfil GETEC', () {
    const cabecalhoGetec = 'tombamento;tomb_anterior;descricao;localizacao;marca;n. serie';
    const csvGetec =
        '$cabecalhoGetec\n'
        '00012345;10;NOTEBOOK LENOVO E14;GETEC;LENOVO;10\n'
        '00012346;0008593;LICENÇA MICROSOFT OFFICE PARA NOTEBOOK;GETEC;;SN123\n'
        '00012347;;MESA DE ESCRITORIO;BAIXAS LOCALIZADAS;;SN456\n'
        '00012348;;IMPRESSORA HP;GETEC - UNIVERSITARIO;HP;SN789\n';

    final padroesGetec = ImportDefaults(
      origemPadraoId: 'setor-ti',
      destinoPadraoId: 'setor-almoxarifado',
      dataPadrao: DateTime(2026, 1, 1),
    );

    Future<PatrimonioImportController> carregarAteMapeamentoGetec(
      ProviderContainer container, {
      String csv = csvGetec,
    }) async {
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      await controller.carregarArquivo(nomeArquivo: 'getec.csv', bytes: _csv(csv));
      controller.confirmarCabecalho();
      return controller;
    }

    Future<void> avancarAteRevisaoGetec(
      PatrimonioImportController controller, {
      String csv = csvGetec,
      Map<String, String> mapeamentoLocalizacoes = const {},
    }) async {
      await controller.carregarArquivo(nomeArquivo: 'getec.csv', bytes: _csv(csv));
      controller.confirmarCabecalho();
      controller.ativarPerfilGetec();
      for (final entry in mapeamentoLocalizacoes.entries) {
        controller.definirMapeamentoLocalizacao(entry.key, entry.value);
      }
      controller.definirPadroes(padroesGetec);
      await controller.analisar();
    }

    test('detecta o perfil GETEC pelos cabeçalhos, sem aplicar mapeamento sozinho', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);

      await carregarAteMapeamentoGetec(container);

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.perfilDetectado, ImportProfileId.getecLegado);
      expect(state.perfilAtivo, ImportProfileId.generico);
      expect(state.mapeamento.colunaPorCampo, isEmpty);
    });

    test('ativarPerfilGetec aplica o mapeamento sugerido e o motivo padrão da GETEC', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);

      final controller = await carregarAteMapeamentoGetec(container);
      controller.ativarPerfilGetec();

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.perfilAtivo, ImportProfileId.getecLegado);
      expect(state.mapeamento.colunaDe(ImportColumnField.numeroPatrimonio), 0);
      expect(state.mapeamento.colunaDe(ImportColumnField.tombamentoAnterior), 1);
      expect(state.mapeamento.colunaDe(ImportColumnField.descricao), 2);
      expect(state.mapeamento.colunaDe(ImportColumnField.setor), 3);
      expect(state.mapeamento.colunaDe(ImportColumnField.marca), 4);
      expect(state.mapeamento.colunaDe(ImportColumnField.numeroSerie), 5);
      expect(state.padroes.motivoPadrao, GetecImportProfile.motivoPadraoSugerido);
    });

    test('ignorarPerfilSugerido mantém o comportamento genérico mesmo com cabeçalhos reconhecidos', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);

      final controller = await carregarAteMapeamentoGetec(container);
      controller.ignorarPerfilSugerido();

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.perfilAtivo, ImportProfileId.generico);
      // sem alias genérico para "tombamento anterior"/"n. serie" com pontuação:
      // o mapeamento automático genérico não preenche essas duas colunas.
      expect(state.mapeamento.colunaDe(ImportColumnField.descricao), 2);
    });

    test('avancarAposPadroes vai para resolverLocalizacoes só quando o perfil GETEC está ativo', () async {
      final repoGenerico = FakePatrimonioRepository();
      final containerGenerico = _criarContainer(repoGenerico);
      addTearDown(containerGenerico.dispose);
      final controllerGenerico = containerGenerico.read(patrimonioImportControllerProvider.notifier);
      await _avancarAteRevisao(
        controllerGenerico,
        bytes: _csv('Patrimônio;Tipo;Marca;Serial;Setor\n00045872;Notebook;Dell;AAA1;GETEC\n'),
      );
      expect(containerGenerico.read(patrimonioImportControllerProvider).step, ImportStep.revisar);

      final repoGetec = FakePatrimonioRepository();
      final containerGetec = _criarContainer(repoGetec);
      addTearDown(containerGetec.dispose);
      final controllerGetec = await carregarAteMapeamentoGetec(containerGetec);
      controllerGetec.ativarPerfilGetec();
      controllerGetec.avancarParaPadroes();
      controllerGetec.definirPadroes(padroesGetec);
      await controllerGetec.avancarAposPadroes();

      expect(
        containerGetec.read(patrimonioImportControllerProvider).step,
        ImportStep.resolverLocalizacoes,
      );
    });

    test('regra do "10": serial e tombamento anterior iguais a "10" viram não informado', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await avancarAteRevisaoGetec(controller);

      final linha = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012345');
      expect(linha.numeroSerie, isNull);
      expect(linha.celulas[ImportColumnField.tombamentoAnterior], isNull);
    });

    test('tombamento anterior real é preservado em observação, sem duplicar ao atualizar', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await avancarAteRevisaoGetec(controller);

      final novo = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012346');
      expect(novo.observacao, contains('Tombamento anterior: 0008593'));

      // Mesmo tombamento anterior, mas o patrimônio já existe e a observação
      // já tem a anotação — não deve duplicar (seção 5).
      final existente = PatrimonioDetalhe(
        patrimonio: Patrimonio(
          id: 'existing-2',
          numeroPatrimonio: '00012346',
          tipoId: 'tipo-notebook',
          status: PatrimonioStatus.disponivel,
          setorAtualId: 'setor-getec',
          observacao: 'Importado da base patrimonial GETEC.\nTombamento anterior: 0008593',
          dataCadastro: DateTime(2025, 1, 1),
          atualizadoEm: DateTime(2025, 1, 1),
        ),
        tipoNome: 'Notebook',
        setorNome: 'GETEC',
      );
      final repo2 = FakePatrimonioRepository(itens: [existente]);
      final container2 = _criarContainer(repo2);
      addTearDown(container2.dispose);
      final controller2 = container2.read(patrimonioImportControllerProvider.notifier);
      await avancarAteRevisaoGetec(controller2);

      final atualizando = container2
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012346');
      final ocorrencias = 'Tombamento anterior: 0008593'
          .allMatches(atualizando.observacao ?? '')
          .length;
      expect(ocorrencias, 1);
    });

    test('localização "BAIXAS LOCALIZADAS" gera aviso de possível baixa, sem bloquear', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await avancarAteRevisaoGetec(controller);

      final linha = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012347');
      expect(linha.possivelBaixa, isTrue);
      expect(linha.status, isNot(ImportRowStatus.erro));
      expect(linha.issues.any((i) => i.message.contains('baixado')), isTrue);
    });

    test('tipo é inferido pela descrição quando não há coluna de tipo mapeada', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await avancarAteRevisaoGetec(controller);

      final notebook = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012345');
      expect(notebook.tipoIdResolvido, 'tipo-notebook');
      expect(notebook.tipoInferidoAutomaticamente, isTrue);

      final licenca = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012346');
      expect(licenca.tipoIdResolvido, 'tipo-software');
    });

    test('mapeamento manual de localização é aplicado à linha correspondente', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await avancarAteRevisaoGetec(
        controller,
        mapeamentoLocalizacoes: {'GETEC - UNIVERSITARIO': 'GETEC'},
      );

      final linha = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012348');
      expect(linha.destinoIdResolvido, 'setor-getec');
      expect(linha.usouDestinoPadrao, isFalse);
    });
  });
}

class _RepositorioContadorConcorrencia implements PatrimonioRepository {
  _RepositorioContadorConcorrencia(this._delegado, this._wrap);

  final FakePatrimonioRepository _delegado;
  final Future<Patrimonio> Function(Future<Patrimonio> Function()) _wrap;

  @override
  Future<Patrimonio> cadastrar({
    required String tipoId,
    required String destinoId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
  }) {
    return _wrap(
      () => _delegado.cadastrar(
        tipoId: tipoId,
        destinoId: destinoId,
        numeroPatrimonio: numeroPatrimonio,
        numeroSerie: numeroSerie,
        marca: marca,
        modelo: modelo,
        descricao: descricao,
        observacao: observacao,
        dataAquisicao: dataAquisicao,
        origemId: origemId,
        responsavelOrigem: responsavelOrigem,
        responsavelDestino: responsavelDestino,
        motivo: motivo,
        observacaoMovimentacao: observacaoMovimentacao,
        dataMovimentacao: dataMovimentacao,
      ),
    );
  }

  @override
  Future<Patrimonio> atualizar({
    required String id,
    String? numeroPatrimonio,
    String? numeroSerie,
    required String tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  }) =>
      _delegado.atualizar(
        id: id,
        numeroPatrimonio: numeroPatrimonio,
        numeroSerie: numeroSerie,
        tipoId: tipoId,
        marca: marca,
        modelo: modelo,
        descricao: descricao,
        observacao: observacao,
        dataAquisicao: dataAquisicao,
      );

  @override
  Future<Patrimonio?> buscarPorId(String id) => _delegado.buscarPorId(id);

  @override
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id) => _delegado.buscarDetalhePorId(id);

  @override
  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio) =>
      _delegado.buscarPorNumeroPatrimonio(numeroPatrimonio);

  @override
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros) =>
      _delegado.buscarPorNumerosPatrimonio(numeros);

  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) =>
      _delegado.buscarNumerosSerieExistentes(numerosSerie);
}
