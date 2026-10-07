import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/app/app.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';

import 'features/auth/fake_auth_repository.dart';

void main() {
  testWidgets(
    'Sem sessão, o app abre na tela de login com nome e subtítulo do InvTec',
    (WidgetTester tester) async {
      final fake = FakeAuthRepository();
      addTearDown(fake.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(fake)],
          child: const InvTecApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('InvTec'), findsOneWidget);
      expect(find.text('Sistema de Controle Patrimonial'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'E-mail'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Senha'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);

      // Etapa 5: cadastro público de usuários passa a existir (fica
      // PENDING até aprovação administrativa) — a tela de login expõe o
      // link para a nova rota `/cadastro`.
      expect(find.widgetWithText(TextButton, 'Criar conta'), findsOneWidget);
    },
  );
}
