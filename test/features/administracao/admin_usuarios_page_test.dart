import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/administracao/data/usuario_admin_repository_supabase.dart';
import 'package:invtec/features/administracao/presentation/admin_usuarios_page.dart';
import 'package:invtec/features/auth/domain/profile.dart';

import 'fake_usuario_admin_repository.dart';

Profile _usuario({
  required String id,
  required String nome,
  String? email = 'usuario@example.com',
  ProfilePerfil perfil = ProfilePerfil.operador,
  ProfileAccessStatus accessStatus = ProfileAccessStatus.pending,
  String? cpf = '52998224725',
  int rejectionCount = 0,
}) {
  return Profile(
    id: id,
    nome: nome,
    email: email,
    perfil: perfil,
    ativo: accessStatus == ProfileAccessStatus.active,
    criadoEm: DateTime.utc(2026, 1, 1),
    atualizadoEm: DateTime.utc(2026, 1, 1),
    accessStatus: accessStatus,
    rejectionCount: rejectionCount,
    cpf: cpf,
  );
}

Future<void> _pumpAdminUsuariosPage(
  WidgetTester tester, {
  required FakeUsuarioAdminRepository repo,
  double? largura,
}) async {
  if (largura != null) {
    tester.view.physicalSize = Size(largura, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [usuarioAdminRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: AdminUsuariosPage())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('listagem por aba', () {
    testWidgets('aba Pendentes mostra só pendentes e o contador bate', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: '1', nome: 'Ana Pendente', accessStatus: ProfileAccessStatus.pending),
          _usuario(id: '2', nome: 'Beto Pendente', accessStatus: ProfileAccessStatus.pending),
          _usuario(id: '3', nome: 'Carla Ativa', accessStatus: ProfileAccessStatus.active),
        ],
      );
      await _pumpAdminUsuariosPage(tester, repo: repo);

      expect(find.text('Ana Pendente'), findsOneWidget);
      expect(find.text('Beto Pendente'), findsOneWidget);
      expect(find.text('Carla Ativa'), findsNothing);
      expect(find.text('Pendentes (2)'), findsOneWidget);
    });

    testWidgets('contador de pendentes continua visível na aba Ativos', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: '1', nome: 'Ana Pendente', accessStatus: ProfileAccessStatus.pending),
          _usuario(id: '3', nome: 'Carla Ativa', accessStatus: ProfileAccessStatus.active),
        ],
      );
      await _pumpAdminUsuariosPage(tester, repo: repo);

      await tester.tap(find.text('Ativos'));
      await tester.pumpAndSettle();

      expect(find.text('Carla Ativa'), findsOneWidget);
      expect(find.text('Ana Pendente'), findsNothing);
      expect(find.text('Pendentes (1)'), findsOneWidget);
    });

    testWidgets('aba Rejeitados e Bloqueados mostram os usuários certos', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: '1', nome: 'Rejeitado Um', accessStatus: ProfileAccessStatus.rejected),
          _usuario(id: '2', nome: 'Bloqueado Um', accessStatus: ProfileAccessStatus.blocked),
        ],
      );
      await _pumpAdminUsuariosPage(tester, repo: repo);

      await tester.tap(find.text('Rejeitados'));
      await tester.pumpAndSettle();
      expect(find.text('Rejeitado Um'), findsOneWidget);

      await tester.tap(find.text('Bloqueados'));
      await tester.pumpAndSettle();
      expect(find.text('Bloqueado Um'), findsOneWidget);
    });

    testWidgets('estado vazio mostra mensagem específica da aba', (tester) async {
      await _pumpAdminUsuariosPage(tester, repo: FakeUsuarioAdminRepository());

      expect(find.text('Nenhuma solicitação pendente.'), findsOneWidget);
    });
  });

  group('busca', () {
    testWidgets('busca filtra a listagem via o repositório (debounce)', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: '1', nome: 'Ana Pendente', accessStatus: ProfileAccessStatus.pending),
          _usuario(id: '2', nome: 'Beto Pendente', accessStatus: ProfileAccessStatus.pending),
        ],
      );
      await _pumpAdminUsuariosPage(tester, repo: repo);

      expect(find.text('Ana Pendente'), findsOneWidget);
      expect(find.text('Beto Pendente'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Ana');
      await tester.pump(const Duration(milliseconds: 100));
      // Ainda dentro da janela de debounce: nada deve ter mudado.
      expect(find.text('Beto Pendente'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Ana Pendente'), findsOneWidget);
      expect(find.text('Beto Pendente'), findsNothing);
    });

    testWidgets('busca sem resultado mostra mensagem específica', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: '1', nome: 'Ana Pendente')],
      );
      await _pumpAdminUsuariosPage(tester, repo: repo);

      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum usuário encontrado para "inexistente".'), findsOneWidget);
    });
  });

  group('CPF legado', () {
    testWidgets('CPF nulo mostra "Não informado" e não quebra a tela', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: '1', nome: 'Conta Legada', cpf: null)],
      );
      await _pumpAdminUsuariosPage(tester, repo: repo);

      expect(find.text('Não informado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('responsividade', () {
    for (final largura in [1440.0, 1024.0, 800.0, 390.0]) {
      testWidgets('${largura.toInt()}px: listagem sem overflow/exceções', (tester) async {
        final repo = FakeUsuarioAdminRepository(
          usuarios: [
            _usuario(id: '1', nome: 'Ana Pendente', accessStatus: ProfileAccessStatus.pending),
            _usuario(
              id: '2',
              nome: 'Beto Sem CPF',
              accessStatus: ProfileAccessStatus.pending,
              cpf: null,
            ),
          ],
        );
        await _pumpAdminUsuariosPage(tester, repo: repo, largura: largura);

        expect(find.text('Ana Pendente'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
