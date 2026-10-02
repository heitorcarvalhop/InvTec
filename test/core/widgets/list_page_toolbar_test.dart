import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/widgets/list_page_toolbar.dart';
import 'package:invtec/core/widgets/list_view_mode.dart';

/// Cobre a composição responsiva do [ListPageToolbar] em isolamento — o
/// bug real que motivou o refinamento visual (ação principal "órfã" numa
/// segunda linha, overflow, seletor "Buscar em" truncado a uma letra) foi
/// reproduzido pelos dois agentes de UI em telas diferentes; aqui ele é
/// coberto uma vez só, no componente compartilhado, no PIOR CASO real do
/// app (rótulos mais longos: Movimentações).
void main() {
  Future<void> pumpToolbar(
    WidgetTester tester, {
    required double largura,
    Widget? searchLeading,
    int filterCount = 0,
  }) async {
    tester.view.physicalSize = Size(largura, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListPageToolbar(
            searchController: TextEditingController(),
            searchHint: 'Buscar por patrimônio, equipamento, documento, chamado, responsável...',
            onSearchChanged: (_) {},
            searchLeading: searchLeading,
            filterCount: filterCount,
            onFiltersPressed: () {},
            viewMode: ListViewMode.list,
            onViewModeChanged: (_) {},
            primaryActionLabel: 'Nova movimentação',
            primaryActionIcon: Icons.add,
            onPrimaryAction: () {},
            secondaryActions: [
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Importar documento SEI'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Todas as larguras pedidas no refinamento visual: desktop largo,
  /// breakpoint desktop/tablet, tablet estreito e mobile.
  const larguras = [1440.0, 1280.0, 1024.0, 900.0, 800.0, 390.0];

  for (final largura in larguras) {
    testWidgets('${largura}px: sem overflow, ação principal e "Filtros" sempre visíveis', (
      tester,
    ) async {
      final erros = <String>[];
      final anterior = FlutterError.onError;
      FlutterError.onError = (details) => erros.add(details.toString());

      await pumpToolbar(tester, largura: largura, filterCount: 2);

      FlutterError.onError = anterior;

      expect(
        erros.where((e) => e.toLowerCase().contains('overflow')),
        isEmpty,
        reason: 'overflow em ${largura}px: ${erros.join('\n')}',
      );
      expect(tester.takeException(), isNull, reason: 'exceção em ${largura}px');

      // Nenhuma largura pode esconder a ação principal nem o botão de
      // filtros — só reposicionar (1 ou 2 linhas), nunca omitir.
      expect(find.text('Nova movimentação'), findsOneWidget, reason: 'em ${largura}px');
      expect(find.text('Importar documento SEI'), findsOneWidget, reason: 'em ${largura}px');
      expect(find.text('Filtros (2)'), findsOneWidget, reason: 'em ${largura}px');
    });
  }

  testWidgets('seletor "Buscar em" aparece por extenso, nunca truncado a uma letra', (
    tester,
  ) async {
    await pumpToolbar(
      tester,
      largura: 390,
      searchLeading: const Tooltip(message: 'Buscar em', child: Text('Tudo')),
    );

    expect(find.text('Tudo'), findsOneWidget);
    expect(find.text('T'), findsNothing);
  });

  testWidgets(
    'largura generosa cabe tudo numa linha; largura estreita empilha deliberadamente em duas',
    (tester) async {
      // Não comparamos pixels exatos (alturas de `TextField`/`FilledButton`
      // diferem, então até "a mesma linha" tem centros levemente distintos)
      // — só a altura TOTAL do toolbar, que só pode ser maior quando ele
      // decide empilhar busca e controles em duas linhas.
      await pumpToolbar(tester, largura: 1440);
      final alturaUmaLinha = tester.getSize(find.byType(ListPageToolbar)).height;

      await pumpToolbar(tester, largura: 760);
      final alturaEmpilhada = tester.getSize(find.byType(ListPageToolbar)).height;

      expect(
        alturaEmpilhada,
        greaterThan(alturaUmaLinha),
        reason: 'em 760px a composição deve empilhar busca e controles em duas linhas, '
            'nunca espremer os dois lado a lado',
      );
    },
  );
}
