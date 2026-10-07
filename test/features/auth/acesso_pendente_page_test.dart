import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/acesso_pendente_page.dart';

import 'fake_auth_repository.dart';

Profile _profilePendente({String? cpf}) => Profile(
  id: 'fake-user-id',
  nome: 'Fulano de Tal',
  email: 'fulano@invtec.com',
  perfil: ProfilePerfil.operador,
  ativo: false,
  criadoEm: DateTime(2026, 1, 1),
  atualizadoEm: DateTime(2026, 1, 1),
  accessStatus: ProfileAccessStatus.pending,
  rejectionCount: 0,
  cpf: cpf,
);

Future<FakeAuthRepository> _pumpPendentePage(WidgetTester tester, {String? cpf}) async {
  final fake = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profilePendente(cpf: cpf),
  );
  addTearDown(fake.dispose);

  final router = GoRouter(
    initialLocation: '/acesso/pendente',
    routes: [
      GoRoute(path: '/acesso/pendente', builder: (context, state) => const AcessoPendentePage()),
      GoRoute(path: '/login', builder: (context, state) => const Scaffold(body: Text('PAGINA_LOGIN'))),
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
  group('AcessoPendentePage', () {
    testWidgets('mostra nome, e-mail e CPF mascarado do profile em sessão', (tester) async {
      await _pumpPendentePage(tester, cpf: '52998224725');

      expect(find.text('Solicitação enviada'), findsOneWidget);
      expect(find.text('Fulano de Tal'), findsOneWidget);
      expect(find.text('fulano@invtec.com'), findsOneWidget);
      expect(find.text('***.***.247-25'), findsOneWidget);
      // CPF completo nunca aparece em claro.
      expect(find.textContaining('529.982.247-25'), findsNothing);
    });

    testWidgets('CPF nulo (conta legada) mostra "Não informado" sem quebrar', (tester) async {
      await _pumpPendentePage(tester, cpf: null);

      expect(find.text('Não informado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('botão "Atualizar status" chama atualizarStatus no controller', (tester) async {
      final fake = await _pumpPendentePage(tester, cpf: '52998224725');

      // atualizarStatus() -> invalidateSelf() -> build() roda de novo,
      // reabrindo observeProfileChanges com o profile recarregado — prova
      // direta de que o botão não é decorativo (ver AuthController.
      // atualizarStatus).
      expect(fake.observeProfileChangesCallCount, 1);

      await tester.tap(find.widgetWithText(FilledButton, 'Atualizar status'));
      await tester.pumpAndSettle();

      expect(fake.observeProfileChangesCallCount, 2);
    });

    testWidgets('botão "Sair" chama signOut no controller', (tester) async {
      final fake = await _pumpPendentePage(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sair'));
      await tester.pumpAndSettle();

      expect(fake.signOutCallCount, 1);
    });

    testWidgets('renderiza sem overflow em largura estreita (390px)', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpPendentePage(tester, cpf: '52998224725');

      expect(tester.takeException(), isNull);
    });
  });
}
