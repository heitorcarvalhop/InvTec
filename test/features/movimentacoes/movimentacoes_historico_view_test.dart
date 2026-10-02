import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/domain/ordenacao_direcao.dart';
import 'package:invtec/core/widgets/active_filter_chip.dart';
import 'package:invtec/core/widgets/list_view_mode.dart';
import 'package:invtec/core/widgets/sortable_header_label.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_ordenacao.dart';
import 'package:invtec/features/movimentacoes/presentation/movimentacoes_page.dart';
import 'package:invtec/features/movimentacoes/presentation/movimentacoes_view_mode_controller.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/movimentacao_cards_grid.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/movimentacoes_desktop_table.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/movimentacoes_mobile_list.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/fake_auth_repository.dart';
import '../setores/fake_setor_repository.dart';
import 'fake_movimentacao_repository.dart';

/// Cobre a camada visual de ordenação/visualização da aba "Histórico de
/// movimentações" (ver prompt): cabeçalhos ordenáveis, o controle "Ordenar
/// por", a troca Lista/Cards (e sua persistência) e os chips de filtro
/// ativo. A ordenação em si (a lógica de comparação) já é coberta pelos
/// testes do [FakeMovimentacaoRepository]/`MovimentacoesController` — aqui
/// o que se verifica é que a UI aciona exatamente os mesmos parâmetros.
Profile _profile() => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

MovimentacaoListagemItem _item(
  String id, {
  MovimentacaoTipo tipo = MovimentacaoTipo.transferencia,
  String? patrimonioNumero,
  String? setorOrigemId,
  String? setorDestinoId,
  String? setorOrigemNome,
  String? setorDestinoNome,
  DateTime? dataMovimentacao,
}) {
  return MovimentacaoListagemItem(
    id: id,
    tipo: tipo,
    patrimonioId: 'patrimonio-$id',
    patrimonioNumero: patrimonioNumero,
    setorOrigemId: setorOrigemId,
    setorDestinoId: setorDestinoId,
    setorOrigemNome: setorOrigemNome,
    setorDestinoNome: setorDestinoNome,
    dataMovimentacao: dataMovimentacao ?? DateTime(2026, 1, 10, 14, 30),
  );
}

Future<ProviderContainer> _pumpPage(
  WidgetTester tester, {
  required FakeMovimentacaoRepository movimentacaoRepo,
  List<Setor>? setores,
  Size tamanho = const Size(1280, 800),
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile());
  addTearDown(fakeAuth.dispose);

  late final ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        movimentacaoRepositoryProvider.overrideWithValue(movimentacaoRepo),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: setores)),
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const MaterialApp(home: Scaffold(body: MovimentacoesPage()));
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _abrirFiltros(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.filter_list));
  await tester.pumpAndSettle();
}

Future<void> _trocarParaCards(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Cards'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('cabeçalhos ordenáveis (Lista)', () {
    testWidgets('clicar em "Data": ASC no 1º clique, DESC no 2º, padrão no 3º', (tester) async {
      final repo = FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]);
      await _pumpPage(tester, movimentacaoRepo: repo);

      await tester.tap(find.widgetWithText(SortableHeaderLabel, 'Data'));
      await tester.pumpAndSettle();
      expect(repo.ultimaChamadaListar?['ordenarPor'], MovimentacaoOrdenacaoCampo.data);
      expect(repo.ultimaChamadaListar?['ordenacaoDirecao'], OrdenacaoDirecao.asc);
      expect(
        tester.widget<SortableHeaderLabel>(find.widgetWithText(SortableHeaderLabel, 'Data')).state,
        SortIndicatorState.ascending,
      );

      await tester.tap(find.widgetWithText(SortableHeaderLabel, 'Data'));
      await tester.pumpAndSettle();
      expect(repo.ultimaChamadaListar?['ordenarPor'], MovimentacaoOrdenacaoCampo.data);
      expect(repo.ultimaChamadaListar?['ordenacaoDirecao'], OrdenacaoDirecao.desc);
      expect(
        tester.widget<SortableHeaderLabel>(find.widgetWithText(SortableHeaderLabel, 'Data')).state,
        SortIndicatorState.descending,
      );

      await tester.tap(find.widgetWithText(SortableHeaderLabel, 'Data'));
      await tester.pumpAndSettle();
      expect(repo.ultimaChamadaListar?['ordenarPor'], isNull, reason: 'terceiro clique volta ao padrão da tela');
      expect(
        tester.widget<SortableHeaderLabel>(find.widgetWithText(SortableHeaderLabel, 'Data')).state,
        SortIndicatorState.none,
      );
    });

    testWidgets('Origem e Destino ordenam de forma independente', (tester) async {
      final repo = FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]);
      await _pumpPage(tester, movimentacaoRepo: repo);

      await tester.tap(find.widgetWithText(SortableHeaderLabel, 'Origem'));
      await tester.pumpAndSettle();
      expect(repo.ultimaChamadaListar?['ordenarPor'], MovimentacaoOrdenacaoCampo.origem);
      expect(
        tester.widget<SortableHeaderLabel>(find.widgetWithText(SortableHeaderLabel, 'Destino')).state,
        SortIndicatorState.none,
        reason: 'clicar em Origem não marca Destino como se estivesse ordenando',
      );

      await tester.tap(find.widgetWithText(SortableHeaderLabel, 'Destino'));
      await tester.pumpAndSettle();
      expect(repo.ultimaChamadaListar?['ordenarPor'], MovimentacaoOrdenacaoCampo.destino);
      expect(
        tester.widget<SortableHeaderLabel>(find.widgetWithText(SortableHeaderLabel, 'Origem')).state,
        SortIndicatorState.none,
        reason: 'Destino assumir a ordenação some com o estado "ativo" de Origem',
      );
    });
  });

  group('controle "Ordenar por"', () {
    testWidgets('funciona igual aos cliques de cabeçalho', (tester) async {
      final repo = FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]);
      await _pumpPage(tester, movimentacaoRepo: repo);

      await tester.tap(find.text('Ordenar por:'));
      // Abre o dropdown "Ordenar por".
      await tester.tap(find.byType(DropdownButton<MovimentacaoOrdenacaoCampo>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Patrimônio').last);
      await tester.pumpAndSettle();

      expect(repo.ultimaChamadaListar?['ordenarPor'], MovimentacaoOrdenacaoCampo.patrimonio);
      expect(repo.ultimaChamadaListar?['ordenacaoDirecao'], OrdenacaoDirecao.asc);

      // O botão de direção alterna exatamente como um segundo clique no
      // mesmo cabeçalho alternaria (ASC -> DESC). Localizado pelo tooltip
      // (não pelo ícone): o próprio cabeçalho "Patrimônio" da tabela também
      // mostra uma seta ascendente agora que está ordenando por ele.
      await tester.tap(find.byTooltip('Ordem crescente'));
      await tester.pumpAndSettle();
      expect(repo.ultimaChamadaListar?['ordenarPor'], MovimentacaoOrdenacaoCampo.patrimonio);
      expect(repo.ultimaChamadaListar?['ordenacaoDirecao'], OrdenacaoDirecao.desc);
    });
  });

  group('modo de visualização (Lista/Cards)', () {
    testWidgets('padrão é Lista', (tester) async {
      await _pumpPage(tester, movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1')]));

      expect(find.byType(MovimentacoesDesktopTable), findsOneWidget);
      expect(find.byType(MovimentacaoCardsGrid), findsNothing);
    });

    testWidgets('trocar para Cards mostra o grid e persiste entre sessões', (tester) async {
      final container = await _pumpPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]),
      );

      await _trocarParaCards(tester);

      expect(find.byType(MovimentacaoCardsGrid), findsOneWidget);
      expect(find.byType(MovimentacoesDesktopTable), findsNothing);
      expect(container.read(movimentacoesViewModeControllerProvider).value, ListViewMode.cards);

      // "Fecha e reabre": novo container, mesmo SharedPreferences mock.
      await _pumpPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]),
      );
      expect(find.byType(MovimentacaoCardsGrid), findsOneWidget, reason: 'preferência persistida');
    });

    testWidgets('trocar Lista -> Cards preserva a ordenação escolhida', (tester) async {
      final repo = FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]);
      await _pumpPage(tester, movimentacaoRepo: repo);

      await tester.tap(find.widgetWithText(SortableHeaderLabel, 'Tipo'));
      await tester.pumpAndSettle();
      expect(repo.ultimaChamadaListar?['ordenarPor'], MovimentacaoOrdenacaoCampo.tipo);

      await _trocarParaCards(tester);

      expect(find.byType(MovimentacaoCardsGrid), findsOneWidget);
      // A troca de modo de visualização não recarrega com outra ordenação —
      // o "Ordenar por" (sempre visível) continua mostrando Tipo.
      expect(repo.ultimaChamadaListar?['ordenarPor'], MovimentacaoOrdenacaoCampo.tipo);
      expect(find.widgetWithText(DropdownButton<MovimentacaoOrdenacaoCampo>, 'Tipo'), findsOneWidget);
    });

    testWidgets('mobile sempre usa a lista compacta, mesmo com preferência "Cards" salva', (tester) async {
      await _pumpPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]),
      );
      await _trocarParaCards(tester);
      expect(find.byType(MovimentacaoCardsGrid), findsOneWidget);

      // Mesma preferência salva ("Cards"), mas agora numa janela mobile.
      await _pumpPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]),
        tamanho: const Size(390, 800),
      );
      expect(find.byType(MovimentacoesMobileList), findsOneWidget);
      expect(find.byType(MovimentacaoCardsGrid), findsNothing);
    });
  });

  group('chips de filtro ativo', () {
    testWidgets('aparecem quando um filtro é aplicado e removem só aquele filtro', (tester) async {
      final repo = FakeMovimentacaoRepository(
        itens: [
          _item('1', patrimonioNumero: '100', tipo: MovimentacaoTipo.entrada),
          _item('2', patrimonioNumero: '200', tipo: MovimentacaoTipo.baixa),
        ],
      );
      await _pumpPage(
        tester,
        movimentacaoRepo: repo,
        setores: [Setor(id: 'setor-1', nome: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1))],
      );

      expect(find.byType(ActiveFilterChip), findsNothing, reason: 'sem filtro ativo, sem chip');

      await _abrirFiltros(tester);
      final campoTipo = find.widgetWithText(DropdownButtonFormField<MovimentacaoTipo?>, 'Tipo');
      await tester.ensureVisible(campoTipo);
      await tester.tap(campoTipo);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Baixa').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActiveFilterChip, 'Tipo: Baixa'), findsOneWidget);

      // Remover pelo chip (não pelo dropdown) limpa só o filtro de Tipo.
      final chip = tester.widget<ActiveFilterChip>(find.widgetWithText(ActiveFilterChip, 'Tipo: Baixa'));
      chip.onRemove();
      await tester.pumpAndSettle();

      expect(find.byType(ActiveFilterChip), findsNothing);
      expect(repo.ultimaChamadaListar?['tipo'], isNull);
    });

    testWidgets('chip de Setor usa o rótulo compacto e some ao remover', (tester) async {
      final repo = FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100', setorOrigemId: 'setor-1')]);
      await _pumpPage(
        tester,
        movimentacaoRepo: repo,
        setores: [Setor(id: 'setor-1', nome: 'Gerência de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1))],
      );

      await _abrirFiltros(tester);
      final campoSetor = find.widgetWithText(DropdownButtonFormField<String?>, 'Setor');
      await tester.ensureVisible(campoSetor);
      await tester.tap(campoSetor);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GETEC').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActiveFilterChip, 'Setor: GETEC'), findsOneWidget);

      final chip = tester.widget<ActiveFilterChip>(find.widgetWithText(ActiveFilterChip, 'Setor: GETEC'));
      chip.onRemove();
      await tester.pumpAndSettle();

      expect(find.byType(ActiveFilterChip), findsNothing);
      expect(repo.ultimaChamadaListar?['setorId'], isNull);
    });
  });

  group('responsividade (sem overflow/exceções)', () {
    for (final tamanho in [const Size(1440, 900), const Size(1024, 800), const Size(800, 600), const Size(390, 800)]) {
      for (final modo in ['lista', 'cards']) {
        testWidgets('${tamanho.width.toInt()}x${tamanho.height.toInt()} em modo $modo', (tester) async {
          await _pumpPage(
            tester,
            movimentacaoRepo: FakeMovimentacaoRepository(
              itens: List.generate(
                5,
                (i) => _item(
                  '$i',
                  patrimonioNumero: 'P$i',
                  setorOrigemNome: 'Gerência de Tecnologia',
                  setorDestinoNome: 'Gerência de Licenciamento de Atividades Estratégicas',
                ),
              ),
            ),
            tamanho: tamanho,
          );

          if (modo == 'cards' && tamanho.width >= 600) {
            await _trocarParaCards(tester);
          }

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
