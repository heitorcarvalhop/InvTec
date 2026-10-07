import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/auth_repository.dart';
import 'package:invtec/features/auth/presentation/cadastro_page.dart';

import 'fake_auth_repository.dart';

Future<FakeAuthRepository> _pumpCadastroPage(WidgetTester tester) async {
  final fake = FakeAuthRepository();
  addTearDown(fake.dispose);

  final router = GoRouter(
    initialLocation: '/cadastro',
    routes: [
      GoRoute(path: '/cadastro', builder: (context, state) => const CadastroPage()),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('PAGINA_LOGIN')),
      ),
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

Future<void> _preencherCamposValidos(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Nome completo'), 'Fulano de Tal');
  await tester.enterText(find.widgetWithText(TextFormField, 'CPF'), '52998224725');
  await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'fulano@invtec.com');
  await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'Abcdefghij1!');
  await tester.enterText(find.widgetWithText(TextFormField, 'Confirmar senha'), 'Abcdefghij1!');
}

Icon _iconeDoRequisito(WidgetTester tester, String descricao) {
  final linha = find.ancestor(of: find.text(descricao), matching: find.byType(Row)).first;
  return tester.widget<Icon>(find.descendant(of: linha, matching: find.byType(Icon)));
}

void main() {
  group('CadastroPage', () {
    testWidgets('nome vazio mostra erro de validação e não chama o repositório', (tester) async {
      final fake = await _pumpCadastroPage(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'CPF'), '52998224725');
      await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'fulano@invtec.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'Abcdefghij1!');
      await tester.enterText(find.widgetWithText(TextFormField, 'Confirmar senha'), 'Abcdefghij1!');

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome completo.'), findsOneWidget);
      expect(fake.signUpCallCount, 0);
    });

    testWidgets('CPF inválido mostra erro de validação e não chama o repositório', (tester) async {
      final fake = await _pumpCadastroPage(tester);
      await _preencherCamposValidos(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'CPF'), '11111111111');

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(find.text('Informe um CPF válido.'), findsOneWidget);
      expect(fake.signUpCallCount, 0);
    });

    testWidgets('e-mail inválido mostra erro de validação e não chama o repositório', (tester) async {
      final fake = await _pumpCadastroPage(tester);
      await _preencherCamposValidos(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'nao-e-email');

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(find.text('Informe um e-mail válido.'), findsOneWidget);
      expect(fake.signUpCallCount, 0);
    });

    testWidgets('confirmação de senha diferente mostra erro e não chama o repositório', (tester) async {
      final fake = await _pumpCadastroPage(tester);
      await _preencherCamposValidos(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Confirmar senha'), 'OutraSenha1!');

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(find.text('As senhas não coincidem.'), findsOneWidget);
      expect(fake.signUpCallCount, 0);
    });

    testWidgets('senha fraca mostra erro de validação e não chama o repositório', (tester) async {
      final fake = await _pumpCadastroPage(tester);
      await _preencherCamposValidos(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'fraca');
      await tester.enterText(find.widgetWithText(TextFormField, 'Confirmar senha'), 'fraca');

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(find.text('A senha não atende a todos os requisitos.'), findsOneWidget);
      expect(fake.signUpCallCount, 0);
    });

    testWidgets('checklist de requisitos de senha atualiza a cada tecla digitada', (tester) async {
      await _pumpCadastroPage(tester);

      // Nenhum requisito satisfeito inicialmente.
      expect(_iconeDoRequisito(tester, 'Mínimo de 12 caracteres').icon, Icons.circle_outlined);
      expect(_iconeDoRequisito(tester, 'Um número').icon, Icons.circle_outlined);

      // Satisfaz só "minúscula" e "mínimo de 12 caracteres" (12 letras minúsculas).
      await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'abcdefghijkl');
      await tester.pump();

      expect(_iconeDoRequisito(tester, 'Mínimo de 12 caracteres').icon, Icons.check_circle);
      expect(_iconeDoRequisito(tester, 'Uma letra minúscula').icon, Icons.check_circle);
      expect(_iconeDoRequisito(tester, 'Uma letra maiúscula').icon, Icons.circle_outlined);
      expect(_iconeDoRequisito(tester, 'Um número').icon, Icons.circle_outlined);
      expect(_iconeDoRequisito(tester, 'Um caractere especial').icon, Icons.circle_outlined);

      // Satisfaz todos os 5 requisitos.
      await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'Abcdefghij1!');
      await tester.pump();

      for (final descricao in const [
        'Mínimo de 12 caracteres',
        'Uma letra maiúscula',
        'Uma letra minúscula',
        'Um número',
        'Um caractere especial',
      ]) {
        expect(_iconeDoRequisito(tester, descricao).icon, Icons.check_circle);
      }
    });

    testWidgets('CPF digitado recebe máscara visual 000.000.000-00', (tester) async {
      await _pumpCadastroPage(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'CPF'), '52998224725');
      await tester.pump();

      expect(find.text('529.982.247-25'), findsOneWidget);
    });

    testWidgets('dados válidos com sessão criada chama o repositório e mostra confirmação', (tester) async {
      final fake = await _pumpCadastroPage(tester);
      fake.signUpResult = const AuthSignUpResult(sessaoCriada: true);
      await _preencherCamposValidos(tester);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(fake.signUpCallCount, 1);
      expect(find.text('Cadastro realizado com sucesso.'), findsOneWidget);
    });

    testWidgets('confirmação de e-mail exigida é exibida destacada na própria tela', (tester) async {
      final fake = await _pumpCadastroPage(tester);
      fake.signUpResult = const AuthSignUpResult(sessaoCriada: false);
      await _preencherCamposValidos(tester);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(
        find.text('Cadastro criado. Verifique seu e-mail para confirmar a conta e depois faça login.'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Voltar para o login'));
      await tester.tap(find.widgetWithText(FilledButton, 'Voltar para o login'));
      await tester.pumpAndSettle();

      expect(find.text('PAGINA_LOGIN'), findsOneWidget);
    });

    testWidgets('erro do servidor mostra mensagem traduzida, nunca o texto bruto', (tester) async {
      final fake = await _pumpCadastroPage(tester);
      fake.signUpError = Exception('erro bruto do servidor nunca deveria aparecer');
      await _preencherCamposValidos(tester);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      expect(find.textContaining('erro bruto'), findsNothing);
      expect(
        find.text('Não foi possível concluir a operação. Tente novamente em alguns instantes.'),
        findsOneWidget,
      );
    });

    testWidgets('renderiza sem overflow em largura estreita (390px)', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpCadastroPage(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
