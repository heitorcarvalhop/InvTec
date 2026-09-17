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
import 'package:invtec/features/patrimonios/domain/patrimonio_search_field.dart';
import 'package:invtec/features/patrimonios/domain/patrimonios_resultado.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/getec_import_profile.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/import_profile_id.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

final _tipos = [
  TipoPatrimonio(id: 'tipo-notebook', nome: 'Notebook', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  TipoPatrimonio(id: 'tipo-software', nome: 'Software / Licença', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  TipoPatrimonio(id: 'tipo-mobiliario', nome: 'Mobiliário', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
final _setores = [
  Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-almoxarifado', nome: 'Almoxarifado', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-ti', nome: 'TI', sigla: 'TI', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
final _localizacoes = [
  Localizacao(
    id: 'loc-universitario',
    setorId: 'setor-getec',
    nome: 'GETEC - Universitário',
    ativo: true,
    criadoEm: DateTime(2026, 1, 1),
  ),
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
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
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
    PatrimonioSearchField campoBusca = PatrimonioSearchField.tudo,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
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
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
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
    PatrimonioSearchField campoBusca = PatrimonioSearchField.tudo,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros) =>
      _delegado.buscarPorNumerosPatrimonio(numeros);

  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) =>
      _delegado.buscarNumerosSerieExistentes(numerosSerie);
}

ProviderContainer _criarContainer(
  PatrimonioRepository repositorio, {
  FakeLocalizacaoRepository? repositorioLocalizacoes,
}) {
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
      setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
      localizacaoRepositoryProvider.overrideWithValue(
        repositorioLocalizacoes ?? FakeLocalizacaoRepository(localizacoes: _localizacoes),
      ),
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
        '00012345;10;NOTEBOOK LENOVO E14;GETEC - UNIV ABREVIADO;LENOVO;10\n'
        '00012346;0008593;LICENÇA MICROSOFT OFFICE PARA NOTEBOOK;GETEC - UNIV ABREVIADO;;SN123\n'
        '00012347;;MESA DE ESCRITORIO;BAIXAS LOCALIZADAS;;SN456\n'
        '00012348;;IMPRESSORA HP;GETEC - UNIVERSITARIO;HP;SN789\n';

    // origemPadraoId de propósito ausente: a planilha GETEC não tem coluna
    // de origem, e a seção 14 da correção de modelagem tornou isso
    // aceitável só para este perfil (origemDispensada) — nunca um setor
    // fictício "Origem não informada".
    final padroesGetec = ImportDefaults(
      destinoPadraoId: 'setor-getec',
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
      expect(state.mapeamento.colunaDe(ImportColumnField.localizacao), 3);
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

    test(
      'localização "BAIXAS LOCALIZADAS" (PROMPT 8.12): NÃO gera mais aviso de possível '
      'baixa, fica sem localização por regra conhecida, e segue a regra normal de cadastro',
      () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await avancarAteRevisaoGetec(controller);

        final linha = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '00012347');

        // PROMPT 8.12: nova definição de negócio — "BAIXAS LOCALIZADAS" é um
        // bem recuperado/relocalizado, nunca indício de baixa atual. O
        // importador não gera mais o aviso, nem marca `possivelBaixa`.
        expect(linha.possivelBaixa, isFalse);
        expect(linha.issues.any((i) => i.message.contains('baixado')), isFalse);
        expect(linha.status, isNot(ImportRowStatus.erro));
        expect(linha.status, isNot(ImportRowStatus.aviso));

        // "BAIXAS LOCALIZADAS" continua um valor CONHECIDO sem localização
        // física — localizacaoIdResolvida fica null por decisão do
        // importador, nunca pendente (não é um caso "não resolvido").
        expect(linha.localizacaoIdResolvida, isNull);
        expect(linha.localizacaoSemLocalizacaoPorRegra, isTrue);
        expect(linha.localizacaoPendente, isFalse);
        expect(linha.localizacaoOficialAusente, isFalse);

        // Nota histórica preservada em observacao (campo já existente, sem
        // alterar schema) — documentação textual, nunca status/comportamento.
        expect(linha.observacao, contains('retornado à GETEC'));

        // O patrimônio segue a regra normal de cadastro: nunca vira BAIXADO
        // automaticamente por causa do texto de localização — cadastrar()
        // nem aceita status como parâmetro, então isso é estruturalmente
        // impossível, mas confirmamos aqui o estado final mesmo assim.
        await controller.confirmarImportacao();
        expect(repo.ultimoCadastro!.containsKey('status'), isFalse);
        final criado = await repo.buscarPorNumeroPatrimonio('00012347');
        expect(criado?.status, isNot(PatrimonioStatus.baixado));
        expect(criado?.status, PatrimonioStatus.disponivel);
      },
    );

    group('PROMPT 8.15.1 — nota histórica de BAIXAS LOCALIZADAS sobrevive a mapeamento manual', () {
      const notaRecuperacao =
          'Bem anteriormente baixado por não localização; localizado novamente e retornado à GETEC nesta carga.';
      final localizacoesComSituacaoPa = [
        ..._localizacoes,
        Localizacao(
          id: 'loc-situacao-pa',
          setorId: 'setor-getec',
          nome: 'Situação/Situada - PA',
          ativo: true,
          criadoEm: DateTime(2026, 1, 1),
        ),
      ];

      test('sem mapeamento manual: nota presente (comportamento já existente, preservado)', () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await avancarAteRevisaoGetec(controller);

        final linha = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '00012347');
        expect(linha.observacao, contains(notaRecuperacao));
      });

      test(
        'BUG CONFIRMADO (piloto real): mapeada manualmente para SITUAÇÃO/SITUADA - PA continua com a nota',
        () async {
          final repo = FakePatrimonioRepository();
          final container = _criarContainer(
            repo,
            repositorioLocalizacoes: FakeLocalizacaoRepository(localizacoes: localizacoesComSituacaoPa),
          );
          addTearDown(container.dispose);
          final controller = container.read(patrimonioImportControllerProvider.notifier);

          await avancarAteRevisaoGetec(
            controller,
            mapeamentoLocalizacoes: {'BAIXAS LOCALIZADAS': 'loc-situacao-pa'},
          );

          final linha = container
              .read(patrimonioImportControllerProvider)
              .linhas
              .firstWhere((l) => l.numeroPatrimonio == '00012347');

          // a decisão manual de localização atual vence normalmente...
          expect(linha.localizacaoIdResolvida, 'loc-situacao-pa');
          expect(linha.localizacaoSemLocalizacaoPorRegra, isFalse);
          // ...mas a origem semântica da linha (veio de BAIXAS LOCALIZADAS)
          // não pode ser apagada só porque a localização final mudou.
          expect(linha.observacao, contains(notaRecuperacao));
        },
      );

      test(
        'BAIXAS LOCALIZADAS + tombamento anterior: as duas informações coexistem, sem uma substituir a outra',
        () async {
          final repo = FakePatrimonioRepository();
          final container = _criarContainer(repo);
          addTearDown(container.dispose);
          final controller = container.read(patrimonioImportControllerProvider.notifier);

          const csvComTombamento =
              '$cabecalhoGetec\n'
              '00099999;0859312;MONITOR RECUPERADO;BAIXAS LOCALIZADAS;;SN999\n';
          await avancarAteRevisaoGetec(controller, csv: csvComTombamento);

          final linha = container
              .read(patrimonioImportControllerProvider)
              .linhas
              .firstWhere((l) => l.numeroPatrimonio == '00099999');
          expect(linha.observacao, contains('Tombamento anterior: 0859312'));
          expect(linha.observacao, contains(notaRecuperacao));
        },
      );

      test('reanálise não duplica a nota nem o tombamento anterior', () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        const csvComTombamento =
            '$cabecalhoGetec\n'
            '00099999;0859312;MONITOR RECUPERADO;BAIXAS LOCALIZADAS;;SN999\n';
        await avancarAteRevisaoGetec(controller, csv: csvComTombamento);
        await controller.analisar(); // reanálise, sem recarregar o arquivo

        final linha = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '00099999');
        expect('Tombamento anterior: 0859312'.allMatches(linha.observacao ?? '').length, 1);
        expect(notaRecuperacao.allMatches(linha.observacao ?? '').length, 1);
      });

      test('linha normal (não veio de BAIXAS LOCALIZADAS) nunca recebe a nota', () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await avancarAteRevisaoGetec(controller);

        final linha = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '00012348');
        expect(linha.observacao ?? '', isNot(contains(notaRecuperacao)));
      });
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
        mapeamentoLocalizacoes: {'GETEC - UNIV ABREVIADO': 'loc-universitario'},
      );

      final linha = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012345');
      expect(linha.localizacaoIdResolvida, 'loc-universitario');
      // gerência continua vindo do destino padrão fixo, nunca da coluna de
      // localização (seção 30/31) — localização não é setor.
      expect(linha.destinoIdResolvido, 'setor-getec');
    });

    test('localização que já bate com o nome cadastrado resolve sozinha, sem mapeamento manual', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await avancarAteRevisaoGetec(controller);

      final linha = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012348');
      expect(linha.localizacaoIdResolvida, 'loc-universitario');
    });

    test(
      'localização sem decisão fica pendente e BLOQUEIA o envio '
      '(PROMPT 8.9.1: nunca importa uma localização desconhecida sem decisão)',
      () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await avancarAteRevisaoGetec(controller);

        final linha = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '00012345');
        expect(linha.localizacaoIdResolvida, isNull);
        expect(linha.localizacaoPendente, isTrue);
        expect(linha.localizacaoTexto, 'GETEC - UNIV ABREVIADO');
        expect(linha.status, ImportRowStatus.erro);
        expect(linha.seraEnviada, isFalse);
        expect(
          linha.issues.any(
            (i) => i.severity == ImportIssueSeverity.erro && i.message.contains('ainda não foi resolvida'),
          ),
          isTrue,
        );
      },
    );

    test(
      'decisão explícita "importar sem localização" desbloqueia a linha e envia com localização null',
      () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await controller.carregarArquivo(nomeArquivo: 'getec.csv', bytes: _csv(csvGetec));
        controller.confirmarCabecalho();
        controller.ativarPerfilGetec();
        controller.definirImportarSemLocalizacao('GETEC - UNIV ABREVIADO', true);
        controller.definirPadroes(padroesGetec);
        await controller.analisar();

        final linha = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '00012345');
        expect(linha.localizacaoIdResolvida, isNull);
        expect(linha.localizacaoPendente, isFalse);
        expect(linha.status, isNot(ImportRowStatus.erro));
        expect(linha.seraEnviada, isTrue);
      },
    );

    test(
      'associar manualmente uma localização desconhecida a uma localização existente desbloqueia '
      'a linha e envia com o UUID resolvido',
      () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        // Sem mapeamento: a linha fica bloqueada (mesma planilha do teste acima).
        await avancarAteRevisaoGetec(controller);
        final pendente = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '00012345');
        expect(pendente.status, ImportRowStatus.erro);
        expect(pendente.seraEnviada, isFalse);

        // Usuário mapeia manualmente o texto para uma localização existente
        // e reanalisa — mesmo fluxo real da tela de resolução de localizações.
        controller.definirMapeamentoLocalizacao('GETEC - UNIV ABREVIADO', 'loc-universitario');
        await controller.analisar();

        final resolvida = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '00012345');
        expect(resolvida.localizacaoIdResolvida, 'loc-universitario');
        expect(resolvida.localizacaoPendente, isFalse);
        expect(resolvida.status, isNot(ImportRowStatus.erro));
        expect(resolvida.seraEnviada, isTrue);
      },
    );

    test('origem histórica desconhecida não é erro na carga GETEC (sem setor fictício)', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      // Decide explicitamente "sem localização" para isolar este teste do
      // bloqueio de localização pendente (PROMPT 8.9.1) — o que se quer
      // verificar aqui é exclusivamente o comportamento de origem.
      await controller.carregarArquivo(nomeArquivo: 'getec.csv', bytes: _csv(csvGetec));
      controller.confirmarCabecalho();
      controller.ativarPerfilGetec();
      controller.definirImportarSemLocalizacao('GETEC - UNIV ABREVIADO', true);
      controller.definirPadroes(padroesGetec);
      await controller.analisar();

      final linha = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00012345');
      expect(linha.origemIdResolvido, isNull);
      expect(linha.issues.any((i) => i.message.contains('origem')), isFalse);
      expect(linha.status, isNot(ImportRowStatus.erro));
    });

    group('PROMPT 8.9 — mapeamento oficial de localizações da GETEC', () {
      // Localizações ativas carregadas do Supabase para este grupo: cobre um
      // nome oficial direto ("GETEC - Universitário"), o alvo canônico de um
      // apelido conhecido ("Situação/Situada - PA"), e OMITE de propósito
      // "GETEC - Canidé" — outro nome oficial conhecido, mas ausente da
      // gerência carregada — para testar o cenário de erro do teste 9.
      final localizacoesPrompt89 = [
        Localizacao(
          id: 'loc-universitario',
          setorId: 'setor-getec',
          nome: 'GETEC - Universitário',
          ativo: true,
          criadoEm: DateTime(2026, 1, 1),
        ),
        Localizacao(
          id: 'loc-situacao-pa',
          setorId: 'setor-getec',
          nome: 'Situação/Situada - PA',
          ativo: true,
          criadoEm: DateTime(2026, 1, 1),
        ),
      ];

      const csvPrompt89 =
          '$cabecalhoGetec\n'
          '90000001;;NOTEBOOK LENOVO E14;GETEC - UNIVERSITÁRIO;;SN901\n'
          '90000002;;NOTEBOOK LENOVO E14;SITUAÇÃO - PA;;SN902\n'
          '90000003;;NOTEBOOK LENOVO E14;INTANGÍVEIS;;SN903\n'
          '90000004;;NOTEBOOK LENOVO E14;TI - SOFTWARE;;SN904\n'
          '90000005;;NOTEBOOK LENOVO E14;BAIXAS LOCALIZADAS;;SN905\n'
          '90000006;;NOTEBOOK LENOVO E14;GETEC - CANIDÉ;;SN906\n'
          '90000007;;NOTEBOOK LENOVO E14;LOCAL COMPLETAMENTE DESCONHECIDO;;SN907\n';

      test('"GETEC - UNIVERSITÁRIO" resolve normalmente contra a lista carregada', () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(
          repo,
          repositorioLocalizacoes: FakeLocalizacaoRepository(localizacoes: localizacoesPrompt89),
        );
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await avancarAteRevisaoGetec(controller, csv: csvPrompt89);

        final linha = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '90000001');
        expect(linha.localizacaoIdResolvida, 'loc-universitario');
        expect(linha.localizacaoPendente, isFalse);
        expect(linha.localizacaoOficialAusente, isFalse);
        expect(linha.localizacaoSemLocalizacaoPorRegra, isFalse);
        expect(linha.status, isNot(ImportRowStatus.erro));
      });

      test('"SITUAÇÃO - PA" (forma antiga da planilha) resolve para a localização "SITUAÇÃO/SITUADA - PA"', () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(
          repo,
          repositorioLocalizacoes: FakeLocalizacaoRepository(localizacoes: localizacoesPrompt89),
        );
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await avancarAteRevisaoGetec(controller, csv: csvPrompt89);

        final linha = container
            .read(patrimonioImportControllerProvider)
            .linhas
            .firstWhere((l) => l.numeroPatrimonio == '90000002');
        expect(linha.localizacaoIdResolvida, 'loc-situacao-pa');
        expect(linha.localizacaoTexto, 'SITUAÇÃO - PA');
        expect(linha.localizacaoPendente, isFalse);
        expect(linha.localizacaoOficialAusente, isFalse);
      });

      test(
        '"INTANGÍVEIS"/"TI - SOFTWARE"/"BAIXAS LOCALIZADAS" ficam sem localização por regra '
        'conhecida — nunca pendência, nunca erro',
        () async {
          final repo = FakePatrimonioRepository();
          final container = _criarContainer(
            repo,
            repositorioLocalizacoes: FakeLocalizacaoRepository(localizacoes: localizacoesPrompt89),
          );
          addTearDown(container.dispose);
          final controller = container.read(patrimonioImportControllerProvider.notifier);

          await avancarAteRevisaoGetec(controller, csv: csvPrompt89);

          final linhas = container.read(patrimonioImportControllerProvider).linhas;
          for (final numero in ['90000003', '90000004', '90000005']) {
            final linha = linhas.firstWhere((l) => l.numeroPatrimonio == numero);
            expect(linha.localizacaoIdResolvida, isNull, reason: 'linha $numero');
            expect(linha.localizacaoSemLocalizacaoPorRegra, isTrue, reason: 'linha $numero');
            expect(linha.localizacaoPendente, isFalse, reason: 'linha $numero');
            expect(linha.localizacaoOficialAusente, isFalse, reason: 'linha $numero');
            expect(
              linha.issues.any((i) => i.message.contains('ainda não foi resolvida')),
              isFalse,
              reason: 'linha $numero não deve ter aviso de pendência de localização',
            );
            expect(
              linha.issues.any((i) => i.message.contains('não está cadastrada/ativa')),
              isFalse,
              reason: 'linha $numero não deve ter erro de localização oficial ausente',
            );
          }
        },
      );

      test(
        'nome oficial conhecido mas ausente entre as localizações ativas carregadas gera '
        'erro explícito, nunca null silencioso',
        () async {
          final repo = FakePatrimonioRepository();
          final container = _criarContainer(
            repo,
            repositorioLocalizacoes: FakeLocalizacaoRepository(localizacoes: localizacoesPrompt89),
          );
          addTearDown(container.dispose);
          final controller = container.read(patrimonioImportControllerProvider.notifier);

          await avancarAteRevisaoGetec(controller, csv: csvPrompt89);

          final linha = container
              .read(patrimonioImportControllerProvider)
              .linhas
              .firstWhere((l) => l.numeroPatrimonio == '90000006');
          expect(linha.localizacaoIdResolvida, isNull);
          expect(linha.localizacaoOficialAusente, isTrue);
          expect(linha.localizacaoPendente, isFalse);
          expect(linha.localizacaoSemLocalizacaoPorRegra, isFalse);
          expect(linha.status, ImportRowStatus.erro);
          expect(
            linha.issues.any(
              (i) => i.severity == ImportIssueSeverity.erro && i.message.contains('GETEC - CANIDÉ'),
            ),
            isTrue,
          );

          // erro bloqueia o envio — nunca importa silenciosamente sem a
          // localização esperada.
          expect(linha.seraEnviada, isFalse);
        },
      );

      test(
        'valor completamente desconhecido fica pendente e BLOQUEADO até decisão explícita '
        '(PROMPT 8.9.1)',
        () async {
          final repo = FakePatrimonioRepository();
          final container = _criarContainer(
            repo,
            repositorioLocalizacoes: FakeLocalizacaoRepository(localizacoes: localizacoesPrompt89),
          );
          addTearDown(container.dispose);
          final controller = container.read(patrimonioImportControllerProvider.notifier);

          await avancarAteRevisaoGetec(controller, csv: csvPrompt89);

          final linha = container
              .read(patrimonioImportControllerProvider)
              .linhas
              .firstWhere((l) => l.numeroPatrimonio == '90000007');
          expect(linha.localizacaoIdResolvida, isNull);
          expect(linha.localizacaoPendente, isTrue);
          expect(linha.localizacaoOficialAusente, isFalse);
          expect(linha.localizacaoSemLocalizacaoPorRegra, isFalse);
          // desconhecido é bloqueante, mas NÃO é um erro permanente: nunca
          // vira `localizacaoOficialAusente` (que é o caso "conhecido mas
          // ausente") — o usuário ainda pode resolvê-la na etapa de
          // resolução de localizações.
          expect(linha.status, ImportRowStatus.erro);
          expect(linha.seraEnviada, isFalse);
        },
      );

      test('resolução de localizações carrega a lista do Supabase em lote UMA única vez (proibido N+1)', () async {
        final repo = FakePatrimonioRepository();
        final repoLocalizacoes = FakeLocalizacaoRepository(localizacoes: localizacoesPrompt89);
        final container = _criarContainer(repo, repositorioLocalizacoes: repoLocalizacoes);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await avancarAteRevisaoGetec(controller, csv: csvPrompt89);

        expect(container.read(patrimonioImportControllerProvider).linhas, hasLength(7));
        expect(repoLocalizacoes.listarPorSetorCallCount, 1);
      });
    });

    group('PROMPT 8.10 — preflight real (detecção em lote / zero escrita)', () {
      test(
        'tombamento já existente no banco é detectado e NUNCA tratado como cadastro novo',
        () async {
          final existente = PatrimonioDetalhe(
            patrimonio: Patrimonio(
              id: 'existing-8-10',
              numeroPatrimonio: '00012345',
              tipoId: 'tipo-notebook',
              status: PatrimonioStatus.disponivel,
              setorAtualId: 'setor-getec',
              localizacaoAtualId: 'loc-universitario',
              descricao: 'NOTEBOOK LENOVO E14 (já cadastrado antes desta carga)',
              dataCadastro: DateTime(2025, 1, 1),
              atualizadoEm: DateTime(2025, 1, 1),
            ),
            tipoNome: 'Notebook',
            setorNome: 'GETEC',
            localizacaoNome: 'GETEC - Universitário',
          );
          final repo = FakePatrimonioRepository(itens: [existente]);
          final container = _criarContainer(repo);
          addTearDown(container.dispose);
          final controller = container.read(patrimonioImportControllerProvider.notifier);

          await avancarAteRevisaoGetec(controller);

          final linha = container
              .read(patrimonioImportControllerProvider)
              .linhas
              .firstWhere((l) => l.numeroPatrimonio == '00012345');
          expect(linha.existenteNoBanco, isNotNull);
          expect(linha.existenteNoBanco!.patrimonio.id, 'existing-8-10');
          // detectado como existente — nunca "pronto" (que é o caminho de
          // cadastro NOVO): um conflito de tombamento não pode virar um
          // segundo cadastro silenciosamente.
          expect(linha.status, isNot(ImportRowStatus.pronto));
          expect(linha.status, ImportRowStatus.existente);
        },
      );

      test(
        'comparação da planilha com o banco faz UMA chamada em lote por lista, nunca uma por linha (proibido N+1)',
        () async {
          final repo = FakePatrimonioRepository();
          final container = _criarContainer(repo);
          addTearDown(container.dispose);
          final controller = container.read(patrimonioImportControllerProvider.notifier);

          await avancarAteRevisaoGetec(controller);

          expect(container.read(patrimonioImportControllerProvider).linhas, hasLength(4));
          expect(repo.buscarPorNumerosPatrimonioCallCount, 1);
          expect(repo.buscarNumerosSerieExistentesCallCount, 1);
        },
      );

      test(
        'preflight (carregar → mapear → analisar) nunca chama um método de escrita, '
        'em nenhum repositório',
        () async {
          final repo = FakePatrimonioRepository();
          final repoLocalizacoes = FakeLocalizacaoRepository(localizacoes: _localizacoes);
          final container = _criarContainer(repo, repositorioLocalizacoes: repoLocalizacoes);
          addTearDown(container.dispose);
          final controller = container.read(patrimonioImportControllerProvider.notifier);

          await avancarAteRevisaoGetec(controller);
          // reclassificações adicionais (mapear localização manualmente,
          // decidir "sem localização") continuam sem escrever nada:
          controller.definirMapeamentoLocalizacao('GETEC - UNIV ABREVIADO', 'loc-universitario');
          await controller.analisar();

          expect(repo.cadastrarCallCount, 0);
          expect(repo.atualizarCallCount, 0);
          expect(repoLocalizacoes.criarCallCount, 0);
          expect(repoLocalizacoes.atualizarCallCount, 0);
          expect(repoLocalizacoes.alterarAtivoCallCount, 0);
        },
      );
    });

    group('PROMPT 8.13.1 — destino GETEC resolvido automaticamente (nunca hardcoded)', () {
      test(
        'avancarAposPadroes resolve a gerência GETEC pela sigla e a usa como destino padrão, '
        'mesmo sem o usuário escolher nada no dropdown genérico "Destino padrão"',
        () async {
          final repo = FakePatrimonioRepository();
          final container = _criarContainer(repo);
          addTearDown(container.dispose);
          final controller = await carregarAteMapeamentoGetec(container);
          controller.ativarPerfilGetec();
          controller.avancarParaPadroes();
          // define só a data padrão — nenhum destinoPadraoId manual.
          controller.definirPadroes(ImportDefaults(dataPadrao: DateTime(2026, 1, 1)));

          await controller.avancarAposPadroes();

          final state = container.read(patrimonioImportControllerProvider);
          expect(state.step, ImportStep.resolverLocalizacoes);
          expect(state.padroes.destinoPadraoId, 'setor-getec');
          expect(state.mensagemErro, isNull);
        },
      );

      test(
        'o destinoId efetivamente usado no futuro cadastro é o UUID real da GETEC, '
        'mesmo a planilha não tendo coluna de setor',
        () async {
          final repo = FakePatrimonioRepository();
          final container = _criarContainer(repo);
          addTearDown(container.dispose);
          final controller = await carregarAteMapeamentoGetec(container);
          controller.ativarPerfilGetec();
          controller.avancarParaPadroes();
          controller.definirPadroes(ImportDefaults(dataPadrao: DateTime(2026, 1, 1)));
          await controller.avancarAposPadroes();
          await controller.analisar();

          final linhas = container.read(patrimonioImportControllerProvider).linhas;
          expect(linhas, isNotEmpty);
          expect(linhas.every((l) => l.destinoIdResolvido == 'setor-getec'), isTrue);

          await controller.confirmarImportacao();
          expect(repo.ultimoCadastro!['destinoId'], 'setor-getec');
        },
      );

      test(
        'gerência GETEC ausente entre os setores ativos bloqueia o avanço com mensagem clara, '
        'em vez de seguir sem destino',
        () async {
          final repo = FakePatrimonioRepository();
          final container = ProviderContainer(
            overrides: [
              patrimonioRepositoryProvider.overrideWithValue(repo),
              tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
              setorRepositoryProvider.overrideWithValue(
                FakeSetorRepository(
                  setores: [
                    Setor(id: 'outro', nome: 'Outro Setor', sigla: 'OUTRO', ativo: true, criadoEm: DateTime(2026, 1, 1)),
                  ],
                ),
              ),
              localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: _localizacoes)),
              dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
            ],
          );
          container.listen(patrimonioImportControllerProvider, (_, _) {});
          addTearDown(container.dispose);
          final controller = await carregarAteMapeamentoGetec(container);
          controller.ativarPerfilGetec();
          controller.avancarParaPadroes();
          controller.definirPadroes(ImportDefaults(dataPadrao: DateTime(2026, 1, 1)));

          await controller.avancarAposPadroes();

          final state = container.read(patrimonioImportControllerProvider);
          // não avançou de passo — ficou em configurarPadroes.
          expect(state.step, ImportStep.configurarPadroes);
          expect(state.mensagemErro, isNotNull);
          expect(state.mensagemErro, contains('GETEC'));
        },
      );

      test(
        'gerência GETEC inativa (existe, mas ativo=false) também bloqueia — não é tratada como ausente '
        'silenciosamente nem como presente',
        () async {
          final repo = FakePatrimonioRepository();
          final container = ProviderContainer(
            overrides: [
              patrimonioRepositoryProvider.overrideWithValue(repo),
              tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
              // setoresAtivosParaPatrimonioProvider já filtra por ativo, então
              // uma GETEC inativa nunca chega até a lista de "ativos" — o
              // resultado observável é o mesmo de "ausente".
              setorRepositoryProvider.overrideWithValue(
                FakeSetorRepository(
                  setores: [
                    Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC', ativo: false, criadoEm: DateTime(2026, 1, 1)),
                  ],
                ),
              ),
              localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: _localizacoes)),
              dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
            ],
          );
          container.listen(patrimonioImportControllerProvider, (_, _) {});
          addTearDown(container.dispose);
          final controller = await carregarAteMapeamentoGetec(container);
          controller.ativarPerfilGetec();
          controller.avancarParaPadroes();
          controller.definirPadroes(ImportDefaults(dataPadrao: DateTime(2026, 1, 1)));

          await controller.avancarAposPadroes();

          final state = container.read(patrimonioImportControllerProvider);
          expect(state.step, ImportStep.configurarPadroes);
          expect(state.mensagemErro, isNotNull);
        },
      );
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
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
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
    PatrimonioSearchField campoBusca = PatrimonioSearchField.tudo,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros) =>
      _delegado.buscarPorNumerosPatrimonio(numeros);

  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) =>
      _delegado.buscarNumerosSerieExistentes(numerosSerie);
}
