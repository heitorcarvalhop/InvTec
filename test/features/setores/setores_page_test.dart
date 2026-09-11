import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';
import 'package:invtec/features/setores/presentation/setores_page.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_setor_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

Future<void> _pumpSetoresPage(
  WidgetTester tester, {
  required ProfilePerfil perfil,
  required FakeSetorRepository setorRepo,
}) async {
  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(perfil),
  );
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        setorRepositoryProvider.overrideWithValue(setorRepo),
      ],
      child: const MaterialApp(home: Scaffold(body: SetoresPage())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('estados da lista', () {
    testWidgets('banco vazio mostra mensagem e ação de cadastro para ADMIN', (
      tester,
    ) async {
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: FakeSetorRepository(),
      );

      expect(find.text('Nenhum setor cadastrado.'), findsNothing);
      expect(find.textContaining('Nenhum setor cadastrado.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cadastrar setor'), findsOneWidget);
    });

    testWidgets('listagem mostra os setores retornados, ativos primeiro', (
      tester,
    ) async {
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: FakeSetorRepository(
          setores: [
            Setor(
              id: '1',
              nome: 'Almoxarifado',
              sigla: 'ALM',
              ativo: true,
              criadoEm: DateTime.now(),
            ),
            Setor(
              id: '2',
              nome: 'GETEC',
              sigla: 'GE',
              descricao: 'Gerência de Tecnologia',
              ativo: true,
              criadoEm: DateTime.now(),
            ),
          ],
        ),
      );

      expect(find.text('Almoxarifado'), findsOneWidget);
      expect(find.text('GETEC'), findsOneWidget);
      expect(find.text('Gerência de Tecnologia'), findsOneWidget);
      expect(find.text('Ativo'), findsNWidgets(2));
    });

    testWidgets('busca sem resultado mostra mensagem específica', (
      tester,
    ) async {
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: FakeSetorRepository(
          setores: [
            Setor(
              id: '1',
              nome: 'GETEC',
              ativo: true,
              criadoEm: DateTime.now(),
            ),
          ],
        ),
      );

      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhum setor encontrado para "inexistente".'),
        findsOneWidget,
      );
    });

    testWidgets('busca filtra a listagem via o repositório (debounce)', (
      tester,
    ) async {
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: FakeSetorRepository(
          setores: [
            Setor(id: '1', nome: 'GETEC', ativo: true, criadoEm: DateTime.now()),
            Setor(
              id: '2',
              nome: 'Almoxarifado',
              ativo: true,
              criadoEm: DateTime.now(),
            ),
          ],
        ),
      );

      expect(find.text('GETEC'), findsOneWidget);
      expect(find.text('Almoxarifado'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'gete');
      // Ainda dentro da janela de debounce: nada deve ter mudado.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Almoxarifado'), findsOneWidget);

      // Debounce concluído: a busca server-side (simulada) é aplicada.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('GETEC'), findsOneWidget);
      expect(find.text('Almoxarifado'), findsNothing);
    });
  });

  group('permissões', () {
    final setores = [
      Setor(id: '1', nome: 'GETEC', ativo: true, criadoEm: DateTime.now()),
    ];

    testWidgets('OPERADOR vê os setores mas não vê ações administrativas', (
      tester,
    ) async {
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.operador,
        setorRepo: FakeSetorRepository(setores: setores),
      );

      expect(find.text('GETEC'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Novo setor'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('CONSULTA vê os setores mas não vê ações administrativas', (
      tester,
    ) async {
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.consulta,
        setorRepo: FakeSetorRepository(setores: setores),
      );

      expect(find.text('GETEC'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Novo setor'), findsNothing);
    });

    testWidgets('ADMIN vê a ação "Novo setor"', (tester) async {
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: FakeSetorRepository(setores: setores),
      );

      expect(find.widgetWithText(FilledButton, 'Novo setor'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('GESTOR vê a ação "Novo setor"', (tester) async {
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.gestor,
        setorRepo: FakeSetorRepository(setores: setores),
      );

      expect(find.widgetWithText(FilledButton, 'Novo setor'), findsOneWidget);
    });
  });

  group('formulário', () {
    testWidgets('valida nome obrigatório', (tester) async {
      final repo = FakeSetorRepository();
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: repo,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Novo setor'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome'), findsOneWidget);
      expect(repo.criarCallCount, 0);
    });

    testWidgets('sucesso em criação fecha o diálogo e mostra confirmação', (
      tester,
    ) async {
      final repo = FakeSetorRepository();
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: repo,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Novo setor'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'GETEC');
      await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));
      await tester.pumpAndSettle();

      expect(repo.criarCallCount, 1);
      expect(find.text('Setor cadastrado com sucesso.'), findsOneWidget);
      expect(find.text('GETEC'), findsOneWidget);
    });

    testWidgets('erro de setor duplicado é exibido no formulário', (
      tester,
    ) async {
      final repo = FakeSetorRepository(
        setores: [
          Setor(id: '1', nome: 'GETEC', ativo: true, criadoEm: DateTime.now()),
        ],
      );
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: repo,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Novo setor'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'GETEC');
      await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));
      await tester.pumpAndSettle();

      expect(find.text('Já existe um setor com este nome.'), findsOneWidget);
      // O diálogo permanece aberto para o usuário corrigir.
      expect(find.widgetWithText(TextFormField, 'Nome *'), findsOneWidget);
    });
  });

  group('desativação e reativação', () {
    testWidgets('desativar pede confirmação e mostra feedback de sucesso', (
      tester,
    ) async {
      final repo = FakeSetorRepository(
        setores: [
          Setor(id: '1', nome: 'GETEC', ativo: true, criadoEm: DateTime.now()),
        ],
      );
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: repo,
      );

      await tester.tap(find.byIcon(Icons.block_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Desativar setor?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Desativar'));
      await tester.pumpAndSettle();

      expect(repo.alterarAtivoCallCount, 1);
      expect(find.text('Setor desativado.'), findsOneWidget);
      expect(find.text('Inativo'), findsOneWidget);
    });

    testWidgets('erro ao desativar setor em uso mostra mensagem amigável', (
      tester,
    ) async {
      final repo = FakeSetorRepository(
        setores: [
          Setor(id: '1', nome: 'GETEC', ativo: true, criadoEm: DateTime.now()),
        ],
        idsEmUso: {'1'},
      );
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: repo,
      );

      await tester.tap(find.byIcon(Icons.block_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Desativar'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Este setor possui patrimônios vinculados e não pode ser desativado.',
        ),
        findsOneWidget,
      );
      // Continua ativo.
      expect(find.text('Ativo'), findsOneWidget);
    });

    testWidgets('reativar não pede confirmação e mostra feedback', (
      tester,
    ) async {
      final repo = FakeSetorRepository(
        setores: [
          Setor(id: '1', nome: 'GETEC', ativo: false, criadoEm: DateTime.now()),
        ],
      );
      await _pumpSetoresPage(
        tester,
        perfil: ProfilePerfil.admin,
        setorRepo: repo,
      );

      expect(find.text('Inativo'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('Desativar setor?'), findsNothing);
      expect(repo.alterarAtivoCallCount, 1);
      expect(find.text('Setor reativado.'), findsOneWidget);
      expect(find.text('Ativo'), findsOneWidget);
    });
  });
}
