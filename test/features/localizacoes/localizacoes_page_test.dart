import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

Future<GoRouter> _pumpComRouter(
  WidgetTester tester, {
  required FakeLocalizacaoRepository repo,
  required String initialLocation,
}) async {
  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(ProfilePerfil.admin),
  );
  addTearDown(fakeAuth.dispose);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/setores',
        builder: (context, state) => const Scaffold(body: Text('PAGINA_SETORES')),
        routes: [
          GoRoute(
            path: ':setorId/localizacoes',
            builder: (context, state) {
              final setor = state.extra as Setor? ?? _setorGetec;
              return Scaffold(body: LocalizacoesPage(setor: setor));
            },
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        localizacaoRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('LocalizacoesPage — navegação de volta', () {
    testWidgets('com stack válido (veio de Setores), "Voltar" usa pop e retorna para Setores', (tester) async {
      final router = await _pumpComRouter(
        tester,
        repo: FakeLocalizacaoRepository(),
        initialLocation: '/setores',
      );
      router.push('/setores/${_setorGetec.id}/localizacoes', extra: _setorGetec);
      await tester.pumpAndSettle();

      expect(find.textContaining('Localizações de'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Voltar'));
      await tester.pumpAndSettle();

      expect(find.text('PAGINA_SETORES'), findsOneWidget);
      expect(find.textContaining('Localizações de'), findsNothing);
    });

    testWidgets('sem stack válido (aberta diretamente), "Voltar" cai no fallback /setores', (tester) async {
      await _pumpComRouter(
        tester,
        repo: FakeLocalizacaoRepository(),
        initialLocation: '/setores/${_setorGetec.id}/localizacoes',
      );

      expect(find.textContaining('Localizações de'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Voltar'));
      await tester.pumpAndSettle();

      expect(find.text('PAGINA_SETORES'), findsOneWidget);
    });
  });

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

    testWidgets(
      'estado vazio tem uma única ação primária (header) — sem CTA duplicado no card de estado vazio',
      (tester) async {
        await _pumpLocalizacoesPage(tester, perfil: ProfilePerfil.admin, repo: FakeLocalizacaoRepository());

        // Uma única ação primária na página inteira: o botão de destaque
        // ("Nova localização") do cabeçalho.
        expect(find.widgetWithText(FilledButton, 'Nova localização'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);

        // O card de estado vazio é só explicativo — não duplica a ação do
        // cabeçalho com um segundo botão de cadastro.
        expect(find.widgetWithText(OutlinedButton, 'Cadastrar localização'), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
      },
    );

    testWidgets('OPERADOR (sem permissão) também não vê nenhuma ação no estado vazio', (tester) async {
      await _pumpLocalizacoesPage(tester, perfil: ProfilePerfil.operador, repo: FakeLocalizacaoRepository());

      expect(find.textContaining('não possui localizações'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Nova localização'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
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
