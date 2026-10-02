import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/dashboard/domain/dashboard_stats.dart';
import 'package:invtec/features/dashboard/domain/movimentacao_resumo.dart';
import 'package:invtec/features/dashboard/presentation/dashboard_page.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';

import 'fake_dashboard_repository.dart';

void main() {
  testWidgets('banco vazio: cards mostram 0 e a lista mostra estado vazio', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(
            FakeDashboardRepository(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: DashboardPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total de patrimônios'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('Nenhuma movimentação registrada.'), findsOneWidget);
  });

  testWidgets('com dados: cards mostram as contagens e a lista as movimentações', (
    tester,
  ) async {
    final fake = FakeDashboardRepository(
      stats: const DashboardStats(
        total: 10,
        ativos: 8,
        disponiveis: 5,
        emUso: 4,
        emprestados: 1,
        emManutencao: 2,
        baixados: 2,
      ),
      movimentacoesRecentes: [
        MovimentacaoResumo(
          id: '1',
          tipo: MovimentacaoTipo.transferencia,
          patrimonioLabel: '00045872',
          origemNome: 'GETEC',
          destinoNome: 'Almoxarifado',
          dataMovimentacao: DateTime.utc(2026, 1, 10, 12),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dashboardRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: Scaffold(body: DashboardPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('10'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.textContaining('00045872'), findsOneWidget);
    expect(find.textContaining('GETEC'), findsOneWidget);
  });

  testWidgets('erro: mostra mensagem amigável com opção de tentar novamente', (
    tester,
  ) async {
    final fake = FakeDashboardRepository(
      erro: const AppException('Falha ao carregar estatísticas do dashboard'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dashboardRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: Scaffold(body: DashboardPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível carregar os dados do dashboard.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Tentar novamente'), findsOneWidget);
  });

  group('grade de stat cards responsiva (sem linha com um único card sobrando)', () {
    Future<void> pumpEm(WidgetTester tester, Size tamanho) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository())],
          child: const MaterialApp(home: Scaffold(body: DashboardPage())),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 6 cards: largura >= 1100 de conteúdo cabe numa única fileira de 6;
    // larguras menores distribuem em 3+3, 2+2+2 ou 1 por linha — nunca 5+1.
    for (final tamanho in [const Size(1440, 900), const Size(1024, 768), const Size(800, 600)]) {
      testWidgets('${tamanho.width.toInt()}x${tamanho.height.toInt()}: sem overflow', (tester) async {
        await pumpEm(tester, tamanho);

        expect(tester.takeException(), isNull);
        expect(find.text('Total de patrimônios'), findsOneWidget);
        expect(find.text('Baixados'), findsOneWidget);
      });
    }

    testWidgets('mobile (390x844): sem overflow, cards em coluna(s) estreita(s)', (tester) async {
      await pumpEm(tester, const Size(390, 844));

      expect(tester.takeException(), isNull);
      expect(find.text('Total de patrimônios'), findsOneWidget);
    });

    testWidgets('1440px: os 6 cards ficam todos na mesma fileira (mesmo topo)', (tester) async {
      await pumpEm(tester, const Size(1440, 900));

      final primeiro = tester.getTopLeft(find.text('Total de patrimônios')).dy;
      final ultimo = tester.getTopLeft(find.text('Baixados')).dy;
      expect(primeiro, ultimo);
    });

    testWidgets('800px: os cards ficam em mais de uma fileira (nunca 5+1)', (tester) async {
      await pumpEm(tester, const Size(800, 600));

      final primeiro = tester.getTopLeft(find.text('Total de patrimônios')).dy;
      final ultimo = tester.getTopLeft(find.text('Baixados')).dy;
      expect(ultimo, greaterThan(primeiro));
    });
  });
}
