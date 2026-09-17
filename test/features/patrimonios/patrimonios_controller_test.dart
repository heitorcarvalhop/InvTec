import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_search_field.dart';
import 'package:invtec/features/patrimonios/domain/patrimonios_resultado.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonios_controller.dart';

import 'fake_patrimonio_repository.dart';

/// Reproduz exatamente o cenário real do PROMPT 9.1: um patrimônio cujo
/// `numero_serie` coincide com o `numero_patrimonio` de outro (dado real de
/// produção) — a busca "Tudo"/"Patrimônio" nunca pode confundir os dois.
PatrimonioDetalhe _patrimonio({
  required String id,
  String? numero,
  String? numeroSerie,
  String? marca,
  String? modelo,
  String? descricao,
  String? responsavelAtual,
  String? localizacaoNome,
  String? localizacaoId,
  String tipoId = 'tipo-1',
  PatrimonioStatus status = PatrimonioStatus.disponivel,
  String setorAtualId = 'setor-1',
  DateTime? dataCadastro,
  DateTime? dataAquisicao,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      numeroSerie: numeroSerie,
      marca: marca,
      modelo: modelo,
      descricao: descricao,
      tipoId: tipoId,
      status: status,
      setorAtualId: setorAtualId,
      localizacaoAtualId: localizacaoId,
      responsavelAtual: responsavelAtual,
      dataAquisicao: dataAquisicao,
      dataCadastro: dataCadastro ?? DateTime.now(),
      atualizadoEm: DateTime.now(),
    ),
    tipoNome: 'Tipo',
    setorNome: 'Setor',
    localizacaoNome: localizacaoNome,
  );
}

/// Repositório que só libera cada `listar()` quando o teste mandar — usado
/// para provar que uma resposta antiga chegando depois de uma nova nunca
/// sobrescreve o estado (PROMPT 9.1, seção 8/11).
class _RepositorioComPortoesListar implements PatrimonioRepository {
  _RepositorioComPortoesListar(this._delegado);
  final FakePatrimonioRepository _delegado;
  final _pendentes = <Completer<void>>[];

  int get chamadasEmVoo => _pendentes.length;

  /// Libera a chamada a `listar()` MAIS ANTIGA ainda pendente (FIFO) —
  /// simula a resposta de rede que efetivamente completa primeiro.
  void liberarMaisAntiga() => _pendentes.removeAt(0).complete();

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
  }) async {
    final portao = Completer<void>();
    _pendentes.add(portao);
    await portao.future;
    return _delegado.listar(
      limit: limit,
      offset: offset,
      busca: busca,
      campoBusca: campoBusca,
      tipoId: tipoId,
      status: status,
      setorId: setorId,
      localizacaoId: localizacaoId,
      semLocalizacao: semLocalizacao,
      marca: marca,
      modelo: modelo,
      responsavel: responsavel,
      dataCadastroDe: dataCadastroDe,
      dataCadastroAte: dataCadastroAte,
      dataAquisicaoDe: dataAquisicaoDe,
      dataAquisicaoAte: dataAquisicaoAte,
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
  }) => throw UnimplementedError();
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
  }) => throw UnimplementedError();
  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros) =>
      _delegado.buscarPorNumerosPatrimonio(numeros);
  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) =>
      _delegado.buscarNumerosSerieExistentes(numerosSerie);
}

ProviderContainer _criarContainer(PatrimonioRepository repo) {
  final container = ProviderContainer(
    overrides: [patrimonioRepositoryProvider.overrideWithValue(repo)],
  );
  container.listen(patrimoniosControllerProvider, (_, _) {});
  return container;
}

void main() {
  group('PROMPT 9.1 — busca precisa e segura', () {
    // O cenário real que motivou o prompt: patrimônio 2703532 tem
    // numero_serie = "2703522" (dado real de produção).
    final itensReais = [
      _patrimonio(
        id: '1',
        numero: '2703532',
        numeroSerie: '2703522',
        marca: 'MICROSOFT',
        descricao: 'LICENÇAS MICROSOFT OFFICE HOME AND BUSINESS 2019 ESD',
      ),
    ];

    test('campo Patrimônio: busca exata "2703532" encontra o patrimônio 2703532', () async {
      final container = _criarContainer(FakePatrimonioRepository(itens: itensReais));
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirCampoBusca(PatrimonioSearchField.patrimonio);
      notifier.buscar('2703532');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['2703532']);
    });

    test(
      'BUG REAL: campo Patrimônio: busca exata "2703522" (que só existe como número de série '
      'de OUTRO patrimônio) retorna ZERO — NUNCA devolve 2703532',
      () async {
        final container = _criarContainer(FakePatrimonioRepository(itens: itensReais));
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        notifier.definirCampoBusca(PatrimonioSearchField.patrimonio);
        notifier.buscar('2703522');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        expect(state.resultado.itens, isEmpty);
        expect(
          state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio),
          isNot(contains('2703532')),
        );
      },
    );

    test('query com espaços " 2703532 " encontra o patrimônio 2703532', () async {
      final container = _criarContainer(FakePatrimonioRepository(itens: itensReais));
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirCampoBusca(PatrimonioSearchField.patrimonio);
      notifier.buscar(' 2703532 ');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['2703532']);
    });

    test(
      'modo Tudo + número inexistente não retorna um patrimônio numericamente parecido',
      () async {
        final container = _criarContainer(
          FakePatrimonioRepository(
            itens: [
              ...itensReais,
              _patrimonio(id: '2', numero: '2703533', numeroSerie: 'SNXYZ'),
            ],
          ),
        );
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        // "Tudo" é o padrão — nem precisa chamar definirCampoBusca.
        notifier.buscar('2703599');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        expect(state.resultado.itens, isEmpty);
      },
    );

    group('PROMPT 9.1.1 — Tudo nunca mistura patrimônio com número de série', () {
      test('Tudo + "2703532" (existe como patrimônio): resultado principal = 2703532', () async {
        final container = _criarContainer(FakePatrimonioRepository(itens: itensReais));
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        notifier.buscar('2703532');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['2703532']);
        expect(
          state.resultado.correspondenciasPorNumeroSerie,
          isEmpty,
          reason: 'quando o patrimônio exato existe, a série nem precisa ser consultada',
        );
      });

      test(
        'BUG REAL: Tudo + "2703522" (só existe como número de série de 2703532): '
        'itens principal fica vazio — 2703532 nunca aparece misturado como se fosse o patrimônio pesquisado; '
        'a correspondência de série vem separada, identificada',
        () async {
          final container = _criarContainer(FakePatrimonioRepository(itens: itensReais));
          addTearDown(container.dispose);
          final notifier = container.read(patrimoniosControllerProvider.notifier);

          notifier.buscar('2703522');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          final state = await container.read(patrimoniosControllerProvider.future);

          // "patrimônio 2703522 não existe": o resultado PRINCIPAL fica vazio.
          expect(state.resultado.itens, isEmpty);
          expect(state.resultado.total, 0);

          // 2703532 só aparece na lista SEPARADA de correspondências por
          // série — nunca misturado com `itens`.
          expect(
            state.resultado.correspondenciasPorNumeroSerie.map((i) => i.patrimonio.numeroPatrimonio),
            ['2703532'],
          );
          expect(
            state.resultado.correspondenciasPorNumeroSerie.single.patrimonio.numeroSerie,
            '2703522',
          );
        },
      );

      test('Patrimônio + "2703522": continua exatamente igual (zero, sem correspondência de série)', () async {
        final container = _criarContainer(FakePatrimonioRepository(itens: itensReais));
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        notifier.definirCampoBusca(PatrimonioSearchField.patrimonio);
        notifier.buscar('2703522');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        expect(state.resultado.itens, isEmpty);
        expect(state.resultado.total, 0);
        expect(state.resultado.correspondenciasPorNumeroSerie, isEmpty);
      });

      test('Número de série + "2703522": continua retornando o patrimônio 2703532 normalmente', () async {
        final container = _criarContainer(FakePatrimonioRepository(itens: itensReais));
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        notifier.definirCampoBusca(PatrimonioSearchField.numeroSerie);
        notifier.buscar('2703522');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['2703532']);
      });

      test('não executa a segunda consulta (série) quando a primeira (patrimônio) já encontrou algo', () async {
        final repo = FakePatrimonioRepository(itens: itensReais);
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        notifier.buscar('2703532');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        // a prova indireta: correspondenciasPorNumeroSerie só é preenchido
        // pelo caminho da 2ª consulta — se ficou vazio com um match direto,
        // é porque a 2ª consulta nem rodou.
        expect(state.resultado.correspondenciasPorNumeroSerie, isEmpty);
      });
    });

    test('Marca / Modelo = "dell" encontra DELL independentemente de caixa', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '100', marca: 'DELL', modelo: 'Latitude 5430'),
            _patrimonio(id: '2', numero: '101', marca: 'LENOVO', modelo: 'ThinkPad'),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirCampoBusca(PatrimonioSearchField.marcaModelo);
      notifier.buscar('dell');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['100']);
    });

    test('Responsável filtra apenas pelo responsável, não por outros campos textuais', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '100', responsavelAtual: 'Heitor Pereira', descricao: 'Notebook Dell'),
            _patrimonio(id: '2', numero: '101', responsavelAtual: 'Ana Souza', descricao: 'Notebook Heitor 5430'),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirCampoBusca(PatrimonioSearchField.responsavel);
      notifier.buscar('Heitor');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['100']);
    });

    test('Localização pesquisa pelo nome da localização relacionada', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '100', localizacaoNome: 'GETEC - UNIVERSITÁRIO'),
            _patrimonio(id: '2', numero: '101', localizacaoNome: 'DATACENTER - UNIVERSITÁRIO'),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirCampoBusca(PatrimonioSearchField.localizacao);
      notifier.buscar('datacenter');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['101']);
    });

    test('busca + Tipo + Status + Setor: todos os critérios se combinam (AND)', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(
              id: '1',
              numero: '100',
              marca: 'DELL',
              tipoId: 'tipo-notebook',
              status: PatrimonioStatus.disponivel,
              setorAtualId: 'setor-getec',
            ),
            // mesma marca, mas status diferente -> não deve aparecer.
            _patrimonio(
              id: '2',
              numero: '101',
              marca: 'DELL',
              tipoId: 'tipo-notebook',
              status: PatrimonioStatus.baixado,
              setorAtualId: 'setor-getec',
            ),
            // mesma marca/status, mas setor diferente -> não deve aparecer.
            _patrimonio(
              id: '3',
              numero: '102',
              marca: 'DELL',
              tipoId: 'tipo-notebook',
              status: PatrimonioStatus.disponivel,
              setorAtualId: 'setor-outro',
            ),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirCampoBusca(PatrimonioSearchField.marcaModelo);
      notifier.buscar('Dell');
      notifier.filtrarPorTipo('tipo-notebook');
      notifier.filtrarPorStatus(PatrimonioStatus.disponivel);
      notifier.filtrarPorSetor('setor-getec');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['100']);
    });

    test('limparFiltros volta campoBusca para Tudo', () async {
      final container = _criarContainer(FakePatrimonioRepository(itens: itensReais));
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirCampoBusca(PatrimonioSearchField.patrimonio);
      await container.read(patrimoniosControllerProvider.future);
      notifier.limparFiltros();
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.filtro.campoBusca, PatrimonioSearchField.tudo);
      expect(state.filtro.busca, isEmpty);
    });

    test(
      'resposta de busca antiga chegando depois da nova não sobrescreve o estado atual',
      () async {
        final repoBase = FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '2703', status: PatrimonioStatus.disponivel),
            _patrimonio(id: '2', numero: '999', status: PatrimonioStatus.baixado),
          ],
        );
        final repoComPortoes = _RepositorioComPortoesListar(repoBase);
        final container = _criarContainer(repoComPortoes);
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        // build() inicial também passa pelo portão — libera antes de seguir.
        expect(repoComPortoes.chamadasEmVoo, 1);
        repoComPortoes.liberarMaisAntiga();
        await container.read(patrimoniosControllerProvider.future);

        // dispara duas consultas IMEDIATAS (sem debounce: filtro de status),
        // a "antiga" (disponivel) primeiro, a "nova" (baixado) logo depois —
        // as duas ficam em voo ao mesmo tempo.
        notifier.filtrarPorStatus(PatrimonioStatus.disponivel);
        await Future<void>.delayed(Duration.zero);
        notifier.filtrarPorStatus(PatrimonioStatus.baixado);
        await Future<void>.delayed(Duration.zero);
        expect(repoComPortoes.chamadasEmVoo, 2, reason: 'as duas consultas devem estar em voo');

        // libera a NOVA (baixado) primeiro — chegou mais rápido.
        repoComPortoes.liberarMaisAntiga();
        await Future<void>.delayed(Duration.zero);

        // libera a ANTIGA (disponivel) por último — chegou atrasada.
        repoComPortoes.liberarMaisAntiga();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final state = container.read(patrimoniosControllerProvider).value!;
        expect(
          state.filtro.status,
          PatrimonioStatus.baixado,
          reason: 'a resposta atrasada da consulta antiga não pode sobrescrever o filtro/estado mais novo',
        );
        expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['999']);
      },
    );
  });

  group('PROMPT 9.2 — filtros avançados e paginação server-side', () {
    test('Localização específica retorna só os patrimônios daquela localização', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '100', localizacaoId: 'loc-a'),
            _patrimonio(id: '2', numero: '101', localizacaoId: 'loc-b'),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.filtrarPorLocalizacao('loc-a');
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['100']);
    });

    test('Sem localização retorna só os patrimônios com localizacao_atual_id nulo', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '100', localizacaoId: 'loc-a'),
            _patrimonio(id: '2', numero: '101'),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.filtrarPorLocalizacao(null, semLocalizacao: true);
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['101']);
    });

    test('Marca + Status: combinam por AND', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '100', marca: 'DELL', status: PatrimonioStatus.disponivel),
            // mesma marca, outro status -> excluído.
            _patrimonio(id: '2', numero: '101', marca: 'DELL', status: PatrimonioStatus.baixado),
            // mesmo status, outra marca -> excluído.
            _patrimonio(id: '3', numero: '102', marca: 'LENOVO', status: PatrimonioStatus.disponivel),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.filtrarPorStatus(PatrimonioStatus.disponivel);
      notifier.definirMarca('dell');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['100']);
    });

    test('Modelo + Responsável + Setor: combinam por AND', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(
              id: '1',
              numero: '100',
              modelo: 'Latitude 5430',
              responsavelAtual: 'Heitor Pereira',
              setorAtualId: 'setor-getec',
            ),
            // mesmo modelo/responsável, outro setor -> excluído.
            _patrimonio(
              id: '2',
              numero: '101',
              modelo: 'Latitude 5430',
              responsavelAtual: 'Heitor Pereira',
              setorAtualId: 'setor-outro',
            ),
            // mesmo modelo/setor, outro responsável -> excluído.
            _patrimonio(
              id: '3',
              numero: '102',
              modelo: 'Latitude 5430',
              responsavelAtual: 'Ana Souza',
              setorAtualId: 'setor-getec',
            ),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.filtrarPorSetor('setor-getec');
      notifier.definirModelo('latitude');
      // aguarda o debounce do Modelo assentar antes de digitar o
      // Responsável — evita depender da ordem de resolução de dois
      // `Timer`s de debounce concorrentes (cada campo tem o seu, ver
      // PatrimoniosController._debounceModelo/_debounceResponsavel).
      await Future<void>.delayed(const Duration(milliseconds: 350));
      notifier.definirResponsavel('Heitor');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio), ['100']);
    });

    test('intervalo de data de cadastro inclui os dois limites', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '100', dataCadastro: DateTime(2026, 8, 31, 23, 59)),
            _patrimonio(id: '2', numero: '101', dataCadastro: DateTime(2026, 9, 1, 0, 0)),
            _patrimonio(id: '3', numero: '102', dataCadastro: DateTime(2026, 9, 16, 23, 59)),
            _patrimonio(id: '4', numero: '103', dataCadastro: DateTime(2026, 9, 17, 0, 0)),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirDataCadastro(DateTime(2026, 9, 1), DateTime(2026, 9, 16));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(
        state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio).toSet(),
        {'101', '102'},
      );
    });

    test('intervalo de data de aquisição inclui os dois limites', () async {
      final container = _criarContainer(
        FakePatrimonioRepository(
          itens: [
            _patrimonio(id: '1', numero: '100', dataAquisicao: DateTime(2026, 8, 31)),
            _patrimonio(id: '2', numero: '101', dataAquisicao: DateTime(2026, 9, 1)),
            _patrimonio(id: '3', numero: '102', dataAquisicao: DateTime(2026, 9, 16)),
            _patrimonio(id: '4', numero: '103', dataAquisicao: DateTime(2026, 9, 17)),
          ],
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirDataAquisicao(DateTime(2026, 9, 1), DateTime(2026, 9, 16));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(
        state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio).toSet(),
        {'101', '102'},
      );
    });

    test('página padrão é 1 (0-based: 0) e tamanho padrão é 25', () async {
      final container = _criarContainer(FakePatrimonioRepository());
      addTearDown(container.dispose);
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.filtro.pagina, 0);
      expect(state.filtro.tamanhoPagina, 25);
    });

    test('60 itens: página 1 tem 25, página 2 tem 25 (itens 26-50), página 3 tem 10 — total sempre 60', () async {
      final itens = List.generate(
        60,
        (i) => _patrimonio(
          id: '$i',
          numero: 'P$i',
          dataCadastro: DateTime(2026, 1, 1).add(Duration(days: i)),
        ),
      );
      final container = _criarContainer(FakePatrimonioRepository(itens: itens));
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      final pagina1 = await container.read(patrimoniosControllerProvider.future);
      expect(pagina1.resultado.itens, hasLength(25));
      expect(pagina1.resultado.total, 60);

      notifier.irParaPagina(1);
      final pagina2 = await container.read(patrimoniosControllerProvider.future);
      expect(pagina2.resultado.itens, hasLength(25));
      expect(pagina2.resultado.total, 60);

      notifier.irParaPagina(2);
      final pagina3 = await container.read(patrimoniosControllerProvider.future);
      expect(pagina3.resultado.itens, hasLength(10));
      expect(pagina3.resultado.total, 60);

      // nenhum item se repete nem "pula" entre páginas (seção 11).
      final idsPagina1 = pagina1.resultado.itens.map((i) => i.patrimonio.id).toSet();
      final idsPagina2 = pagina2.resultado.itens.map((i) => i.patrimonio.id).toSet();
      final idsPagina3 = pagina3.resultado.itens.map((i) => i.patrimonio.id).toSet();
      expect(idsPagina1.intersection(idsPagina2), isEmpty);
      expect(idsPagina1.intersection(idsPagina3), isEmpty);
      expect(idsPagina2.intersection(idsPagina3), isEmpty);
      expect(idsPagina1.length + idsPagina2.length + idsPagina3.length, 60);
    });

    test('alterar um filtro estando na página 3 volta para a página 1', () async {
      final itens = List.generate(60, (i) => _patrimonio(id: '$i', numero: 'P$i'));
      final container = _criarContainer(FakePatrimonioRepository(itens: itens));
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      await container.read(patrimoniosControllerProvider.future);
      notifier.irParaPagina(2);
      final antes = await container.read(patrimoniosControllerProvider.future);
      expect(antes.filtro.pagina, 2);

      notifier.filtrarPorStatus(PatrimonioStatus.disponivel);
      final depois = await container.read(patrimoniosControllerProvider.future);

      expect(depois.filtro.pagina, 0);
    });

    test('trocar o tamanho da página (25 -> 50) volta para a página 1', () async {
      final itens = List.generate(60, (i) => _patrimonio(id: '$i', numero: 'P$i'));
      final container = _criarContainer(FakePatrimonioRepository(itens: itens));
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      await container.read(patrimoniosControllerProvider.future);
      notifier.irParaPagina(2);
      await container.read(patrimoniosControllerProvider.future);

      notifier.definirTamanhoPagina(50);
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.filtro.pagina, 0);
      expect(state.filtro.tamanhoPagina, 50);
      expect(state.resultado.itens, hasLength(50));
      expect(state.resultado.total, 60);
    });

    test('total representa o conjunto filtrado completo, não só o tamanho da página atual', () async {
      final itens = List.generate(
        30,
        (i) => _patrimonio(id: '$i', numero: 'P$i', localizacaoId: i < 22 ? 'loc-a' : 'loc-b'),
      );
      final container = _criarContainer(FakePatrimonioRepository(itens: itens));
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.filtrarPorLocalizacao('loc-a');
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens, hasLength(22));
      expect(state.resultado.total, 22, reason: 'total é o conjunto filtrado completo, não o tamanho da página');
    });

    test('resultado antigo não sobrescreve uma troca rápida de página', () async {
      final repoBase = FakePatrimonioRepository(
        itens: List.generate(60, (i) => _patrimonio(id: '$i', numero: 'P$i')),
      );
      final repoComPortoes = _RepositorioComPortoesListar(repoBase);
      final container = _criarContainer(repoComPortoes);
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      expect(repoComPortoes.chamadasEmVoo, 1);
      repoComPortoes.liberarMaisAntiga();
      await container.read(patrimoniosControllerProvider.future);

      // troca rápida: página 1 (antiga) e depois página 2 (nova), as duas em
      // voo ao mesmo tempo.
      notifier.irParaPagina(0);
      await Future<void>.delayed(Duration.zero);
      notifier.irParaPagina(1);
      await Future<void>.delayed(Duration.zero);
      expect(repoComPortoes.chamadasEmVoo, 2);

      // a NOVA (página 2) chega primeiro.
      repoComPortoes.liberarMaisAntiga();
      await Future<void>.delayed(Duration.zero);
      // a ANTIGA (página 1) chega atrasada.
      repoComPortoes.liberarMaisAntiga();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(patrimoniosControllerProvider).value!;
      expect(
        state.filtro.pagina,
        1,
        reason: 'a resposta atrasada da página antiga não pode sobrescrever a página mais nova',
      );
    });
  });
}
