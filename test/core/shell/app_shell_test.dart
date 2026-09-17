import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/app/app.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';

import '../../features/auth/fake_auth_repository.dart';
import '../../features/dashboard/fake_dashboard_repository.dart';
import '../../features/patrimonios/fake_patrimonio_repository.dart';
import '../../features/patrimonios/fake_tipo_patrimonio_repository.dart';
import '../../features/setores/fake_setor_repository.dart';

Profile _adminProfile() => Profile(
  id: 'fake-user-id',
  nome: 'Heitor Pereira',
  email: 'heitor@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

Future<FakeAuthRepository> _pumpAuthenticated(
  WidgetTester tester, {
  required Size windowSize,
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _adminProfile(),
  );
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        patrimonioRepositoryProvider.overrideWithValue(
          FakePatrimonioRepository(),
        ),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(),
        ),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
      ],
      child: const InvTecApp(),
    ),
  );
  await tester.pumpAndSettle();

  return fakeAuth;
}

void main() {
  testWidgets('largura desktop mostra sidebar fixa com os itens de menu', (
    tester,
  ) async {
    await _pumpAuthenticated(tester, windowSize: const Size(1280, 800));

    // "InvTec" aparece duas vezes nesta largura: o título do AppBar e a
    // marca no topo da sidebar (PROMPT 9.3) — ambos legítimos.
    expect(find.text('InvTec'), findsWidgets);
    expect(find.text('Gestão de Patrimônio'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Patrimônios'), findsOneWidget);
    expect(find.text('Movimentações'), findsOneWidget);
    expect(find.text('Setores'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
    expect(find.text('Heitor Pereira'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);

    // Drawer não deve existir nesta largura.
    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets('largura mobile usa Drawer em vez de sidebar fixa', (
    tester,
  ) async {
    await _pumpAuthenticated(tester, windowSize: const Size(390, 844));

    // Sidebar fixa não está visível; itens ficam dentro do Drawer fechado.
    expect(find.text('Patrimônios'), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('Patrimônios'), findsOneWidget);
    expect(find.text('Heitor Pereira'), findsOneWidget);
  });

  testWidgets('navegar para Patrimônios troca o conteúdo mantendo o shell', (
    tester,
  ) async {
    await _pumpAuthenticated(tester, windowSize: const Size(1280, 800));

    await tester.tap(find.text('Patrimônios'));
    await tester.pumpAndSettle();

    expect(
      find.text('Consulte e gerencie os equipamentos cadastrados no InvTec.'),
      findsOneWidget,
    );
    // O shell continua presente (sidebar ainda visível).
    expect(find.text('Movimentações'), findsOneWidget);
  });

  testWidgets('Sair desloga e volta para a tela de login', (tester) async {
    final fakeAuth = await _pumpAuthenticated(
      tester,
      windowSize: const Size(1280, 800),
    );

    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();

    expect(fakeAuth.signOutCallCount, 1);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });
}
