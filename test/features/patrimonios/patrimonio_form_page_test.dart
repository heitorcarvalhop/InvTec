import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonio_form_page.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../auth/fake_auth_repository.dart';
import '../dashboard/fake_dashboard_repository.dart';
import '../setores/fake_setor_repository.dart';
import 'fake_patrimonio_repository.dart';
import 'fake_tipo_patrimonio_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

Future<void> _pumpFormPage(
  WidgetTester tester, {
  ProfilePerfil perfil = ProfilePerfil.admin,
  required FakePatrimonioRepository patrimonioRepo,
  List<TipoPatrimonio>? tipos,
  List<Setor>? setores,
}) async {
  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(perfil),
  );
  addTearDown(fakeAuth.dispose);

  final router = GoRouter(
    initialLocation: '/patrimonios/novo',
    routes: [
      GoRoute(
        path: '/patrimonios/novo',
        builder: (context, state) =>
            const Scaffold(body: PatrimonioFormPage()),
      ),
      GoRoute(
        path: '/patrimonios/:id',
        builder: (context, state) => Scaffold(
          body: Text('DETALHE:${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/setores',
        builder: (context, state) => const Scaffold(body: Text('PAGINA_SETORES')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(tipos: tipos ?? _tiposPadrao),
        ),
        setorRepositoryProvider.overrideWithValue(
          FakeSetorRepository(setores: setores ?? _setoresPadrao),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

final _tiposPadrao = [
  TipoPatrimonio(
    id: 'tipo-1',
    nome: 'Notebook',
    ativo: true,
    criadoEm: DateTime.now(),
  ),
];

final _setoresPadrao = [
  Setor(id: 'setor-1', nome: 'GETEC', ativo: true, criadoEm: DateTime.now()),
];

/// O formulário é mais alto que a viewport padrão de teste (800x600) e
/// fica dentro de um SingleChildScrollView — é preciso rolar até o campo
/// antes de tocar nele, senão o toque cai fora da área visível.
Future<void> _selecionarDropdown(
  WidgetTester tester,
  String rotuloCampo,
  String opcao,
) async {
  final campo = find.widgetWithText(DropdownButtonFormField<String>, rotuloCampo);
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.tap(campo);
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcao).last);
  await tester.pumpAndSettle();
}

Future<void> _tocarBotao(WidgetTester tester, String texto) async {
  final botao = find.widgetWithText(FilledButton, texto);
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
  await tester.tap(botao);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem setores ativos bloqueia o cadastro com mensagem clara', (
    tester,
  ) async {
    await _pumpFormPage(
      tester,
      patrimonioRepo: FakePatrimonioRepository(),
      setores: [],
    );

    expect(
      find.textContaining(
        'Cadastre pelo menos um setor antes de registrar patrimônios.',
      ),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets(
    'sem setores e sem permissão de configurar informa que precisa de um administrador',
    (tester) async {
      await _pumpFormPage(
        tester,
        perfil: ProfilePerfil.operador,
        patrimonioRepo: FakePatrimonioRepository(),
        setores: [],
      );

      expect(
        find.textContaining('administrador ou gestor precisa configurá-los'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Ir para Setores'), findsNothing);
    },
  );

  testWidgets('sem tipos ativos bloqueia o cadastro com mensagem clara', (
    tester,
  ) async {
    await _pumpFormPage(
      tester,
      patrimonioRepo: FakePatrimonioRepository(),
      tipos: [],
    );

    expect(
      find.textContaining('Nenhum tipo de patrimônio está ativo'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('valida tipo e destino obrigatórios', (tester) async {
    final repo = FakePatrimonioRepository();
    await _pumpFormPage(tester, patrimonioRepo: repo);

    await _tocarBotao(tester, 'Cadastrar patrimônio');

    expect(find.text('Selecione o tipo'), findsOneWidget);
    expect(find.text('Selecione o destino'), findsOneWidget);
    expect(repo.cadastrarCallCount, 0);
  });

  testWidgets(
    'cadastro bem sucedido chama o repository com os parâmetros corretos e redireciona para o detalhe',
    (tester) async {
      final repo = FakePatrimonioRepository();
      await _pumpFormPage(tester, patrimonioRepo: repo);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número patrimonial'),
        '  00045872  ',
      );
      await _selecionarDropdown(tester, 'Tipo *', 'Notebook');
      await _selecionarDropdown(tester, 'Destino / Setor atual *', 'GETEC');
      await _tocarBotao(tester, 'Cadastrar patrimônio');

      expect(repo.cadastrarCallCount, 1);
      expect(repo.ultimoCadastro?['tipoId'], 'tipo-1');
      expect(repo.ultimoCadastro?['destinoId'], 'setor-1');
      expect(repo.ultimoCadastro?['numeroPatrimonio'], '  00045872  ');
      // Nunca envia status/setor "corrigido" manualmente: cadastrar() só
      // aceita os parâmetros da RPC, não há como enviar status.
      expect(repo.ultimoCadastro!.containsKey('status'), isFalse);

      expect(find.text('DETALHE:novo-1'), findsOneWidget);
      expect(find.text('Patrimônio cadastrado com sucesso.'), findsOneWidget);
    },
  );

  testWidgets('erro de número duplicado é exibido no formulário', (
    tester,
  ) async {
    final repo = FakePatrimonioRepository(
      itens: [],
    );
    // Pré-popula com um patrimônio de número "00045872" cadastrando-o antes.
    await repo.cadastrar(
      tipoId: 'tipo-1',
      destinoId: 'setor-1',
      numeroPatrimonio: '00045872',
    );

    await _pumpFormPage(tester, patrimonioRepo: repo);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Número patrimonial'),
      '00045872',
    );
    await _selecionarDropdown(tester, 'Tipo *', 'Notebook');
    await _selecionarDropdown(tester, 'Destino / Setor atual *', 'GETEC');
    await _tocarBotao(tester, 'Cadastrar patrimônio');

    expect(find.text('Já existe um patrimônio com este número.'), findsOneWidget);
  });
}
