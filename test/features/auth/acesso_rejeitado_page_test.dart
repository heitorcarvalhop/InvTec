import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/acesso_rejeitado_page.dart';

import 'fake_auth_repository.dart';

Profile _profileRejeitado({String? rejectedReason, int rejectionCount = 1}) => Profile(
  id: 'fake-user-id',
  nome: 'Fulano de Tal',
  email: 'fulano@invtec.com',
  perfil: ProfilePerfil.operador,
  ativo: false,
  criadoEm: DateTime(2026, 1, 1),
  atualizadoEm: DateTime(2026, 1, 1),
  accessStatus: ProfileAccessStatus.rejected,
  rejectionCount: rejectionCount,
  cpf: '52998224725',
  rejectedReason: rejectedReason,
);

Future<FakeAuthRepository> _pumpRejeitadoPage(
  WidgetTester tester, {
  String? rejectedReason,
  int rejectionCount = 1,
}) async {
  final fake = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profileRejeitado(rejectedReason: rejectedReason, rejectionCount: rejectionCount),
  );
  addTearDown(fake.dispose);

  final router = GoRouter(
    initialLocation: '/acesso/rejeitado',
    routes: [
      GoRoute(path: '/acesso/rejeitado', builder: (context, state) => const AcessoRejeitadoPage()),
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
  group('AcessoRejeitadoPage', () {
    testWidgets('mostra o motivo da rejeição quando presente', (tester) async {
      await _pumpRejeitadoPage(tester, rejectedReason: 'Documentação incompleta');

      expect(find.text('Solicitação não aprovada'), findsOneWidget);
      expect(find.text('Documentação incompleta'), findsOneWidget);
    });

    testWidgets('omite a linha de motivo quando null, nunca mostra "null"', (tester) async {
      await _pumpRejeitadoPage(tester, rejectedReason: null);

      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('mostra a contagem de tentativas', (tester) async {
      await _pumpRejeitadoPage(tester, rejectionCount: 2);

      expect(find.text('2 de 3'), findsOneWidget);
    });

    testWidgets('botão "Reenviar solicitação" chama o repositório', (tester) async {
      final fake = await _pumpRejeitadoPage(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Reenviar solicitação'));
      await tester.pumpAndSettle();

      expect(fake.reenviarSolicitacaoCallCount, 1);
    });

    testWidgets('erro ao reenviar mostra mensagem traduzida via SnackBar', (tester) async {
      final fake = await _pumpRejeitadoPage(tester);
      fake.reenviarSolicitacaoError = Exception('erro bruto nunca deveria aparecer');

      await tester.tap(find.widgetWithText(FilledButton, 'Reenviar solicitação'));
      await tester.pumpAndSettle();

      expect(fake.reenviarSolicitacaoCallCount, 1);
      expect(find.textContaining('erro bruto'), findsNothing);
      expect(
        find.text('Não foi possível reenviar a solicitação agora. Tente novamente.'),
        findsOneWidget,
      );
    });

    testWidgets('botão "Sair" chama signOut no controller', (tester) async {
      final fake = await _pumpRejeitadoPage(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sair'));
      await tester.pumpAndSettle();

      expect(fake.signOutCallCount, 1);
    });

    testWidgets('renderiza sem overflow em largura estreita (390px)', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpRejeitadoPage(tester, rejectedReason: 'Documentação incompleta');

      expect(tester.takeException(), isNull);
    });
  });
}
