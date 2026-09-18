import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/presentation/movimentacoes_controller.dart';

import 'fake_movimentacao_repository.dart';

MovimentacaoListagemItem _item(
  String id, {
  MovimentacaoTipo tipo = MovimentacaoTipo.transferencia,
  String? patrimonioNumero,
  String? setorOrigemId,
  String? setorDestinoId,
  String? responsavelOrigem,
  String? responsavelDestino,
  String? numeroDocumento,
  String? numeroChamado,
  DateTime? dataMovimentacao,
}) {
  return MovimentacaoListagemItem(
    id: id,
    tipo: tipo,
    patrimonioId: 'patrimonio-$id',
    patrimonioNumero: patrimonioNumero,
    setorOrigemId: setorOrigemId,
    setorDestinoId: setorDestinoId,
    responsavelOrigem: responsavelOrigem,
    responsavelDestino: responsavelDestino,
    numeroDocumento: numeroDocumento,
    numeroChamado: numeroChamado,
    dataMovimentacao: dataMovimentacao ?? DateTime(2026, 1, 1),
  );
}

ProviderContainer _criarContainer(FakeMovimentacaoRepository repo) {
  final container = ProviderContainer(overrides: [movimentacaoRepositoryProvider.overrideWithValue(repo)]);
  container.listen(movimentacoesControllerProvider, (_, _) {});
  return container;
}

void main() {
  group('PROMPT 10.1 — listagem geral de movimentações', () {
    test('listagem inicial traz os itens do repository', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [_item('1', patrimonioNumero: '100'), _item('2', patrimonioNumero: '200')],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);

      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens, hasLength(2));
      expect(state.resultado.total, 2);
    });

    test('ordenação: mais recente primeiro (data_movimentacao DESC)', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          _item('1', patrimonioNumero: 'antigo', dataMovimentacao: DateTime(2026, 1, 1)),
          _item('2', patrimonioNumero: 'recente', dataMovimentacao: DateTime(2026, 3, 1)),
          _item('3', patrimonioNumero: 'meio', dataMovimentacao: DateTime(2026, 2, 1)),
        ],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);

      final state = await container.read(movimentacoesControllerProvider.future);

      expect(
        state.resultado.itens.map((i) => i.patrimonioNumero),
        ['recente', 'meio', 'antigo'],
      );
    });

    test('busca com debounce filtra por patrimônio/responsável/documento/chamado', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          _item('1', patrimonioNumero: '100'),
          _item('2', responsavelDestino: 'João Silva'),
          _item('3', numeroDocumento: 'DOC-42'),
          _item('4', numeroChamado: 'CHAM-9'),
          _item('5', patrimonioNumero: '999'),
        ],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.buscar('DOC-42');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.id), ['3']);
    });

    test('debounce: resposta de uma digitação anterior nunca sobrescreve a mais recente', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [_item('1', patrimonioNumero: '100'), _item('2', patrimonioNumero: '200')],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.buscar('1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      notifier.buscar('200');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.id), ['2']);
    });

    test('filtro Tipo restringe a listagem', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          _item('1', tipo: MovimentacaoTipo.entrada),
          _item('2', tipo: MovimentacaoTipo.baixa),
        ],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.filtrarPorTipo(MovimentacaoTipo.baixa);
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.id), ['2']);
    });

    test('filtro Setor casa origem OU destino', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          _item('1', setorOrigemId: 'setor-a'),
          _item('2', setorDestinoId: 'setor-a'),
          _item('3', setorOrigemId: 'setor-b', setorDestinoId: 'setor-b'),
        ],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.filtrarPorSetor('setor-a');
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.id), containsAll(['1', '2']));
      expect(state.resultado.itens.map((i) => i.id), isNot(contains('3')));
    });

    test('filtro Período inclui os dois limites', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          _item('1', dataMovimentacao: DateTime(2026, 1, 5)),
          _item('2', dataMovimentacao: DateTime(2026, 1, 10)),
          _item('3', dataMovimentacao: DateTime(2026, 1, 20)),
        ],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.definirPeriodo(DateTime(2026, 1, 5), DateTime(2026, 1, 10));
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.id), ['2', '1']);
    });

    test('PROMPT 10.1.1 — Busca + Setor: combinam por AND', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          // casa a busca ('100') e o setor: deve aparecer.
          _item('1', patrimonioNumero: '100', setorDestinoId: 'setor-a'),
          // casa a busca, mas não o setor: não deve aparecer.
          _item('2', patrimonioNumero: '100-b', setorDestinoId: 'setor-b'),
          // casa o setor, mas não a busca: não deve aparecer.
          _item('3', patrimonioNumero: '999', setorDestinoId: 'setor-a'),
        ],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.buscar('100');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      notifier.filtrarPorSetor('setor-a');
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.id), ['1']);
      expect(state.resultado.total, 1);
    });

    test('PROMPT 10.1.1 — Busca + Setor + Tipo: AND entre os três, count exato', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          _item('1', patrimonioNumero: '100', tipo: MovimentacaoTipo.entrada, setorDestinoId: 'setor-a'),
          // tipo diferente: fora.
          _item('2', patrimonioNumero: '100', tipo: MovimentacaoTipo.baixa, setorDestinoId: 'setor-a'),
          // setor diferente: fora.
          _item('3', patrimonioNumero: '100', tipo: MovimentacaoTipo.entrada, setorDestinoId: 'setor-b'),
          // busca não casa: fora.
          _item('4', patrimonioNumero: '999', tipo: MovimentacaoTipo.entrada, setorDestinoId: 'setor-a'),
        ],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.buscar('100');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      notifier.filtrarPorSetor('setor-a');
      notifier.filtrarPorTipo(MovimentacaoTipo.entrada);
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.id), ['1']);
      expect(state.resultado.total, 1);
    });

    test('Tipo + Setor: combinam por AND', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          _item('1', tipo: MovimentacaoTipo.entrada, setorDestinoId: 'setor-a'),
          _item('2', tipo: MovimentacaoTipo.baixa, setorDestinoId: 'setor-a'),
          _item('3', tipo: MovimentacaoTipo.entrada, setorDestinoId: 'setor-b'),
        ],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.filtrarPorTipo(MovimentacaoTipo.entrada);
      notifier.filtrarPorSetor('setor-a');
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens.map((i) => i.id), ['1']);
    });

    test('limparFiltros volta ao estado inicial (sem tipo/setor/período/busca)', () async {
      final repo = FakeMovimentacaoRepository(
        itens: [_item('1', patrimonioNumero: '100'), _item('2', patrimonioNumero: '200')],
      );
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.filtrarPorTipo(MovimentacaoTipo.baixa);
      await container.read(movimentacoesControllerProvider.future);
      notifier.limparFiltros();
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.filtro.tipo, isNull);
      expect(state.resultado.itens, hasLength(2));
    });

    test('estado vazio: nenhum item retornado pelo repository', () async {
      final container = _criarContainer(FakeMovimentacaoRepository());
      addTearDown(container.dispose);

      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.resultado.itens, isEmpty);
      expect(state.resultado.total, 0);
    });

    test('erro do repository propaga como AsyncError', () async {
      final container = ProviderContainer(
        overrides: [
          movimentacaoRepositoryProvider.overrideWithValue(
            FakeMovimentacaoRepository(erro: AppException('Falha ao listar')),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Aguarda o build (que vai falhar) resolver, sem depender do
      // comportamento exato de `.future` sobre um provider que erra —
      // só observa o AsyncValue final via o próprio container.
      final assinatura = container.listen(movimentacoesControllerProvider, (_, _) {});
      addTearDown(assinatura.close);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(movimentacoesControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<AppException>());
    });
  });

  group('PROMPT 10.1 — paginação server-side', () {
    test('página padrão é 1 (0-based: 0) e tamanho padrão é 25', () async {
      final container = _criarContainer(FakeMovimentacaoRepository());
      addTearDown(container.dispose);

      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.filtro.pagina, 0);
      expect(state.filtro.tamanhoPagina, 25);
    });

    test('60 itens: página 1 tem 25, página 2 tem 25, página 3 tem 10 — total sempre 60', () async {
      final itens = List.generate(
        60,
        (i) => _item('$i', patrimonioNumero: 'P$i', dataMovimentacao: DateTime(2026, 1, 1).subtract(Duration(days: i))),
      );
      final container = _criarContainer(FakeMovimentacaoRepository(itens: itens));
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      var state = await container.read(movimentacoesControllerProvider.future);
      expect(state.resultado.itens, hasLength(25));
      expect(state.resultado.total, 60);

      notifier.irParaPagina(1);
      state = await container.read(movimentacoesControllerProvider.future);
      expect(state.resultado.itens, hasLength(25));

      notifier.irParaPagina(2);
      state = await container.read(movimentacoesControllerProvider.future);
      expect(state.resultado.itens, hasLength(10));
    });

    test('PROMPT 10.1.1 — paginação: sem duplicação e sem lacunas entre páginas', () async {
      final itens = List.generate(
        60,
        (i) => _item('$i', patrimonioNumero: 'P$i', dataMovimentacao: DateTime(2026, 1, 1).subtract(Duration(days: i))),
      );
      final container = _criarContainer(FakeMovimentacaoRepository(itens: itens));
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      final pagina1 = (await container.read(movimentacoesControllerProvider.future)).resultado.itens;
      notifier.irParaPagina(1);
      final pagina2 = (await container.read(movimentacoesControllerProvider.future)).resultado.itens;
      notifier.irParaPagina(2);
      final pagina3 = (await container.read(movimentacoesControllerProvider.future)).resultado.itens;

      final idsPagina1 = pagina1.map((i) => i.id).toSet();
      final idsPagina2 = pagina2.map((i) => i.id).toSet();
      final idsPagina3 = pagina3.map((i) => i.id).toSet();

      // As três páginas não compartilham nenhum id entre si (sem duplicação)
      // e juntas cobrem exatamente os 60 itens (sem lacunas), respeitando a
      // ordenação `data_movimentacao DESC, id DESC`.
      expect(idsPagina1.intersection(idsPagina2), isEmpty);
      expect(idsPagina2.intersection(idsPagina3), isEmpty);
      expect(idsPagina1.intersection(idsPagina3), isEmpty);
      expect({...idsPagina1, ...idsPagina2, ...idsPagina3}, hasLength(60));
    });

    test('trocar um filtro estando em outra página volta para a página 1', () async {
      final itens = List.generate(
        30,
        (i) => _item('$i', dataMovimentacao: DateTime(2026, 1, 1).subtract(Duration(days: i))),
      );
      final container = _criarContainer(FakeMovimentacaoRepository(itens: itens));
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.irParaPagina(1);
      await container.read(movimentacoesControllerProvider.future);
      notifier.filtrarPorTipo(MovimentacaoTipo.transferencia);
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.filtro.pagina, 0);
    });

    test('trocar o tamanho da página (25 -> 50) volta para a página 1', () async {
      final container = _criarContainer(FakeMovimentacaoRepository());
      addTearDown(container.dispose);
      final notifier = container.read(movimentacoesControllerProvider.notifier);

      notifier.irParaPagina(2);
      await container.read(movimentacoesControllerProvider.future);
      notifier.definirTamanhoPagina(50);
      final state = await container.read(movimentacoesControllerProvider.future);

      expect(state.filtro.pagina, 0);
      expect(state.filtro.tamanhoPagina, 50);
    });
  });
}
