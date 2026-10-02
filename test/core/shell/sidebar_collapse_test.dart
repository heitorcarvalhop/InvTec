import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/app/app.dart';
import 'package:invtec/core/shell/widgets/nav_tile.dart';
import 'package:invtec/core/shell/widgets/navigation_sidebar.dart';
import 'package:invtec/core/theme/app_spacing.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/fake_auth_repository.dart';
import '../../features/dashboard/fake_dashboard_repository.dart';
import '../../features/patrimonios/fake_patrimonio_repository.dart';
import '../../features/patrimonios/fake_tipo_patrimonio_repository.dart';
import '../../features/setores/fake_setor_repository.dart';

/// Comportamento da sidebar recolhível (PROMPT "Etapa 2" — item 3/29):
/// expandir/recolher, persistência local, tooltips, estado ativo e
/// recálculo automático do espaço do conteúdo.
void main() {
  Profile adminProfile() => Profile(
    id: 'fake-user-id',
    nome: 'Heitor Pereira',
    email: 'heitor@example.com',
    perfil: ProfilePerfil.admin,
    ativo: true,
    criadoEm: DateTime.utc(2026, 1, 1),
    atualizadoEm: DateTime.utc(2026, 1, 1),
  );

  Future<FakeAuthRepository> pumpApp(WidgetTester tester, {required Size windowSize}) async {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => adminProfile());
    addTearDown(fakeAuth.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
          patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
          tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository()),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
        ],
        child: const InvTecApp(),
      ),
    );
    await tester.pumpAndSettle();
    return fakeAuth;
  }

  Future<void> alternarSidebar(WidgetTester tester) async {
    final recolher = find.byTooltip('Recolher menu');
    final expandir = find.byTooltip('Expandir menu');
    await tester.tap(recolher.evaluate().isNotEmpty ? recolher : expandir);
    await tester.pumpAndSettle();
  }

  // Várias páginas reaproveitam os mesmos textos/ícones dos itens de menu
  // (ex.: título "Dashboard" da própria página, ícone de um stat card) — só
  // dentro da sidebar o rótulo tem o significado de "item de navegação".
  Finder naSidebar(Finder matching) => find.descendant(of: find.byType(NavigationSidebar), matching: matching);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('desktop (sem preferência salva)', () {
    testWidgets('1. sidebar começa expandida', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      expect(naSidebar(find.text('Patrimônios')), findsOneWidget);
      expect(find.text('Gestão de Patrimônio'), findsOneWidget);
    });

    testWidgets('2. clique recolhe a sidebar', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await alternarSidebar(tester);

      expect(naSidebar(find.text('Patrimônios')), findsNothing);
      expect(find.text('Gestão de Patrimônio'), findsNothing);
    });

    testWidgets('3. clique novamente expande de volta', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await alternarSidebar(tester);
      await alternarSidebar(tester);

      expect(naSidebar(find.text('Patrimônios')), findsOneWidget);
    });

    testWidgets('5. sidebar recolhida continua mostrando os ícones', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await alternarSidebar(tester);

      expect(naSidebar(find.byIcon(Icons.dashboard_outlined)), findsOneWidget);
      expect(naSidebar(find.byIcon(Icons.inventory_2_outlined)), findsOneWidget);
      expect(naSidebar(find.byIcon(Icons.swap_horiz_outlined)), findsOneWidget);
      expect(naSidebar(find.byIcon(Icons.apartment_outlined)), findsOneWidget);
      expect(naSidebar(find.byIcon(Icons.settings_outlined)), findsOneWidget);
      expect(naSidebar(find.byIcon(Icons.logout)), findsOneWidget);
    });

    testWidgets('6. sidebar recolhida não mostra os rótulos de navegação', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await alternarSidebar(tester);

      expect(naSidebar(find.text('Dashboard')), findsNothing);
      expect(naSidebar(find.text('Patrimônios')), findsNothing);
      expect(naSidebar(find.text('Movimentações')), findsNothing);
      expect(naSidebar(find.text('Setores')), findsNothing);
      expect(naSidebar(find.text('Configurações')), findsNothing);
      expect(naSidebar(find.text('Sair')), findsNothing);
    });

    testWidgets('7. tooltips com o rótulo continuam disponíveis quando recolhida', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await alternarSidebar(tester);

      expect(find.byTooltip('Dashboard'), findsOneWidget);
      expect(find.byTooltip('Patrimônios'), findsOneWidget);
      expect(find.byTooltip('Movimentações'), findsOneWidget);
      expect(find.byTooltip('Setores'), findsOneWidget);
      expect(find.byTooltip('Configurações'), findsOneWidget);
      expect(find.byTooltip('Sair'), findsOneWidget);
    });

    testWidgets('8. estado ativo continua correto quando recolhida', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await tester.tap(naSidebar(find.text('Patrimônios')));
      await tester.pumpAndSettle();
      await alternarSidebar(tester);

      final selecionados = tester.widgetList<NavTile>(find.byType(NavTile)).where((t) => t.selected).toList();
      expect(selecionados, hasLength(1));
      expect(selecionados.single.item.route, '/patrimonios');
    });

    testWidgets('9. navegar com a sidebar recolhida funciona', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await alternarSidebar(tester);
      await tester.tap(find.byTooltip('Patrimônios'));
      await tester.pumpAndSettle();

      expect(find.text('Consulte e gerencie os equipamentos cadastrados no InvTec.'), findsOneWidget);
    });

    testWidgets('10. navegar não expande a sidebar automaticamente', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await alternarSidebar(tester);
      await tester.tap(find.byTooltip('Patrimônios'));
      await tester.pumpAndSettle();

      expect(naSidebar(find.text('Patrimônios')), findsNothing);
      expect(find.byTooltip('Expandir menu'), findsOneWidget);
    });

    testWidgets('11. tema claro: recolher/expandir funciona sem exceções', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await alternarSidebar(tester);
      expect(tester.takeException(), isNull);
      await alternarSidebar(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('12. tema escuro: recolher/expandir funciona sem exceções', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await tester.tap(find.text('Escuro'));
      await tester.pumpAndSettle();

      await alternarSidebar(tester);
      expect(tester.takeException(), isNull);
      expect(naSidebar(find.byIcon(Icons.inventory_2_outlined)), findsOneWidget);
      await alternarSidebar(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('14. conteúdo ganha espaço horizontal quando a sidebar recolhe', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));

      await tester.tap(find.text('Patrimônios'));
      await tester.pumpAndSettle();

      final legenda = find.text('Consulte e gerencie os equipamentos cadastrados no InvTec.');
      final xAntes = tester.getTopLeft(legenda).dx;

      await alternarSidebar(tester);

      final xDepois = tester.getTopLeft(legenda).dx;
      expect(xDepois, lessThan(xAntes));
      expect(xAntes - xDepois, AppSpacing.sidebarWidth - AppSpacing.sidebarWidthCollapsed);
    });
  });

  group('persistência', () {
    testWidgets('4. preferência de sidebar recolhida persiste entre "aberturas" do app', (tester) async {
      await pumpApp(tester, windowSize: const Size(1280, 800));
      await alternarSidebar(tester);
      expect(find.text('Patrimônios'), findsNothing);

      // "Fecha e reabre o InvTec": novo ProviderScope, novo container — mas
      // o mesmo storage local (SharedPreferences mock compartilhado).
      final fakeAuth2 = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => adminProfile());
      addTearDown(fakeAuth2.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth2),
            dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
            patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
            tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository()),
            setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
          ],
          child: const InvTecApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Patrimônios'), findsNothing);
      expect(find.byTooltip('Patrimônios'), findsOneWidget);
    });
  });

  group('mobile', () {
    testWidgets('13. drawer mobile continua funcionando e não tem botão de recolher', (tester) async {
      await pumpApp(tester, windowSize: const Size(390, 844));

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Patrimônios'), findsOneWidget);
      expect(find.byTooltip('Recolher menu'), findsNothing);
      expect(find.byTooltip('Expandir menu'), findsNothing);
    });
  });
}
