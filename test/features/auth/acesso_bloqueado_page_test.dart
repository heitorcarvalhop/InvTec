import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/acesso_bloqueado_page.dart';

import 'fake_auth_repository.dart';

Profile _profileBloqueado({String? blockedReason, int rejectionCount = 3}) => Profile(
  id: 'fake-user-id',
  nome: 'Fulano de Tal',
  email: 'fulano@invtec.com',
  perfil: ProfilePerfil.operador,
  ativo: false,
  criadoEm: DateTime(2026, 1, 1),
  atualizadoEm: DateTime(2026, 1, 1),
  accessStatus: ProfileAccessStatus.blocked,
  rejectionCount: rejectionCount,
  cpf: '52998224725',
  blockedReason: blockedReason,
);

Future<FakeAuthRepository> _pumpBloqueadoPage(
  WidgetTester tester, {
  String? blockedReason,
  int rejectionCount = 3,
}) async {
  final fake = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profileBloqueado(blockedReason: blockedReason, rejectionCount: rejectionCount),
  );
  addTearDown(fake.dispose);

  final router = GoRouter(
    initialLocation: '/acesso/bloqueado',
    routes: [
      GoRoute(path: '/acesso/bloqueado', builder: (context, state) => const AcessoBloqueadoPage()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('AcessoBloqueadoPage', () {
    testWidgets('mostra o motivo do bloqueio quando presente', (tester) async {
      await _pumpBloqueadoPage(tester, blockedReason: 'Uso indevido do sistema');

      expect(find.text('Acesso bloqueado'), findsOneWidget);
      expect(find.text('Uso indevido do sistema'), findsOneWidget);
    });

    testWidgets('omite a linha de motivo quando null, nunca mostra "null"', (tester) async {
      await _pumpBloqueadoPage(tester, blockedReason: null);

      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('nunca mostra botão de reenvio (diferente da tela REJECTED)', (tester) async {
      await _pumpBloqueadoPage(tester);

      expect(find.widgetWithText(FilledButton, 'Reenviar solicitação'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Atualizar status'), findsOneWidget);
    });

    testWidgets('botão "Atualizar status" chama atualizarStatus no controller', (tester) async {
      final fake = await _pumpBloqueadoPage(tester);

      expect(fake.observeProfileChangesCallCount, 1);

      await tester.tap(find.widgetWithText(FilledButton, 'Atualizar status'));
      await tester.pumpAndSettle();

      expect(fake.observeProfileChangesCallCount, 2);
    });

    testWidgets('botão "Sair" chama signOut no controller', (tester) async {
      final fake = await _pumpBloqueadoPage(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sair'));
      await tester.pumpAndSettle();

      expect(fake.signOutCallCount, 1);
    });

    testWidgets('renderiza sem overflow em largura estreita (390px)', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpBloqueadoPage(tester, blockedReason: 'Uso indevido do sistema');

      expect(tester.takeException(), isNull);
    });
  });
}
