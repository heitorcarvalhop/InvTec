import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/localizacoes/presentation/localizacoes_page.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_localizacao_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

final _setorGetec = Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GE', ativo: true, criadoEm: DateTime(2026, 1, 1));

Future<void> _pumpLocalizacoesPage(
  WidgetTester tester, {
  required ProfilePerfil perfil,
  required FakeLocalizacaoRepository repo,
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
        localizacaoRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: Scaffold(body: LocalizacoesPage(setor: _setorGetec))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LocalizacoesPage — permissões', () {
    testWidgets('ADMIN vê "Nova localização" e ícones de editar/desativar', (tester) async {
      await _pumpLocalizacoesPage(
        tester,
        perfil: ProfilePerfil.admin,
        repo: FakeLocalizacaoRepository(
          localizacoes: [
            Localizacao(id: 'l1', setorId: 'setor-getec', nome: 'Home Office', ativo: true, criadoEm: DateTime(2026, 1, 1)),
          ],
        ),
      );

      expect(find.widgetWithText(FilledButton, 'Nova localização'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.block_outlined), findsOneWidget);
    });

    testWidgets('OPERADOR não vê "Nova localização" nem ícones de gestão (somente leitura)', (tester) async {
      await _pumpLocalizacoesPage(
        tester,
        perfil: ProfilePerfil.operador,
        repo: FakeLocalizacaoRepository(
          localizacoes: [
            Localizacao(id: 'l1', setorId: 'setor-getec', nome: 'Home Office', ativo: true, criadoEm: DateTime(2026, 1, 1)),
          ],
        ),
      );

      expect(find.widgetWithText(FilledButton, 'Nova localização'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.block_outlined), findsNothing);
      // ainda enxerga a localização (leitura permitida)
      expect(find.text('Home Office'), findsOneWidget);
    });

    testWidgets('CONSULTA também é somente leitura', (tester) async {
      await _pumpLocalizacoesPage(
        tester,
        perfil: ProfilePerfil.consulta,
        repo: FakeLocalizacaoRepository(
          localizacoes: [
            Localizacao(id: 'l1', setorId: 'setor-getec', nome: 'Home Office', ativo: true, criadoEm: DateTime(2026, 1, 1)),
          ],
        ),
      );

      expect(find.widgetWithText(FilledButton, 'Nova localização'), findsNothing);
    });
  });

  group('LocalizacoesPage — listagem', () {
    testWidgets('gerência sem localizações mostra estado vazio', (tester) async {
      await _pumpLocalizacoesPage(tester, perfil: ProfilePerfil.admin, repo: FakeLocalizacaoRepository());

      expect(find.textContaining('não possui localizações'), findsOneWidget);
    });

    testWidgets('mostra localizações ativas e inativas com status', (tester) async {
      await _pumpLocalizacoesPage(
        tester,
        perfil: ProfilePerfil.admin,
        repo: FakeLocalizacaoRepository(
          localizacoes: [
            Localizacao(id: 'l1', setorId: 'setor-getec', nome: 'Home Office', ativo: true, criadoEm: DateTime(2026, 1, 1)),
            Localizacao(id: 'l2', setorId: 'setor-getec', nome: 'Datacenter', ativo: false, criadoEm: DateTime(2026, 1, 1)),
            // localização de OUTRA gerência nunca aparece aqui.
            Localizacao(id: 'l3', setorId: 'setor-outro', nome: 'Sala 3', ativo: true, criadoEm: DateTime(2026, 1, 1)),
          ],
        ),
      );

      expect(find.text('Home Office'), findsOneWidget);
      expect(find.text('Datacenter'), findsOneWidget);
      expect(find.text('Sala 3'), findsNothing);
      expect(find.text('Ativa'), findsOneWidget);
      expect(find.text('Inativa'), findsOneWidget);
    });

    testWidgets('cadastro de nova localização pelo formulário aparece na lista', (tester) async {
      final repo = FakeLocalizacaoRepository();
      await _pumpLocalizacoesPage(tester, perfil: ProfilePerfil.admin, repo: repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Nova localização'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'Home Office');
      await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));
      await tester.pumpAndSettle();

      expect(repo.criarCallCount, 1);
      expect(find.text('Home Office'), findsOneWidget);
    });
  });
}
