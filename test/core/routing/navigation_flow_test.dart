import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/core/shell/bottom_nav.dart';
import 'package:invtec/app/app.dart';
import 'package:invtec/core/config/platform_info.dart';
import 'package:invtec/core/routing/nav_location.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/notificacoes/data/app_notification_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../features/auth/fake_auth_repository.dart';
import '../../features/auth/fake_permissions_repository.dart';
import '../../features/dashboard/fake_dashboard_repository.dart';
import '../../features/notificacoes/fake_app_notification_repository.dart';
import '../../features/patrimonios/fake_mobile_scanner_platform.dart';
import '../../features/patrimonios/fake_patrimonio_repository.dart';
import '../../features/patrimonios/fake_tipo_patrimonio_repository.dart';
import '../../features/setores/fake_setor_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
  accessStatus: ProfileAccessStatus.active,
  rejectionCount: 0,
);

class _Env {
  _Env(this.router, this.scanner);
  final GoRouter router;
  final FakeMobileScannerPlatform scanner;
  String get path => NavLocation.pathAtual(router);
}

Future<_Env> _pump(
  WidgetTester tester, {
  double largura = 390,
  ProfilePerfil perfil = ProfilePerfil.admin,
  bool android = true,
}) async {
  tester.view.physicalSize = Size(largura, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final scanner = FakeMobileScannerPlatform();
  MobileScannerPlatform.instance = scanner;
  final auth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(perfil),
  );
  addTearDown(auth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isAndroidProvider.overrideWithValue(android),
        authRepositoryProvider.overrideWithValue(auth),
        permissionsRepositoryProvider.overrideWithValue(
          FakePermissionsRepository.paraPerfil(perfil),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        patrimonioRepositoryProvider.overrideWithValue(
          FakePatrimonioRepository(),
        ),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(),
        ),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
        appNotificationRepositoryProvider.overrideWithValue(
          FakeAppNotificationRepository(),
        ),
      ],
      child: const InvTecApp(),
    ),
  );
  await tester.pumpAndSettle();
  final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
  return _Env(router, scanner);
}

int? _abaSelecionada(WidgetTester tester) {
  final f = find.byType(InvTecBottomNav);
  return f.evaluate().isEmpty
      ? null
      : tester.widget<InvTecBottomNav>(f).selectedIndex;
}

Future<void> _voltarAndroid(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _push(WidgetTester tester, _Env env, String rota) async {
  env.router.push(rota);
  await tester.pumpAndSettle();
}

void main() {
  group('NavLocation (fonte única)', () {
    test('cada aba corresponde a UMA rota exata', () {
      expect(NavLocation.abaDe('/dashboard'), NavTab.inicio);
      expect(NavLocation.abaDe('/patrimonios'), NavTab.patrimonios);
      expect(NavLocation.abaDe('/patrimonios/escanear'), NavTab.escanear);
      expect(NavLocation.abaDe('/movimentacoes'), NavTab.movimentacoes);
      expect(NavLocation.abaDe('/setores'), isNull);
      expect(NavTab.values.length, 4);
      expect(NavLocation.ehNivelSuperior('/setores'), isTrue);
    });

    test('rotas internas e de menu NUNCA caem em Início por omissão', () {
      for (final r in [
        '/patrimonios/novo',
        '/patrimonios/abc-123',
        '/patrimonios/importar',
        '/patrimonios/inventario-rapido',
        '/patrimonios/retificar-unidade',
        '/movimentacoes/m1',
        '/setores/s1/localizacoes',
        '/configuracoes',
        '/administracao/usuarios',
        '/administracao/usuarios/u1',
        '/qualquer-coisa',
      ]) {
        expect(NavLocation.abaDe(r), isNull, reason: r);
      }
    });

    test('pai lógico e nível superior', () {
      expect(NavLocation.paiDe('/patrimonios/novo'), '/patrimonios');
      expect(NavLocation.paiDe('/setores/s1/localizacoes'), '/setores');
      expect(NavLocation.paiDe('/movimentacoes/m1'), '/movimentacoes');
      expect(
        NavLocation.paiDe('/administracao/usuarios/u1'),
        '/administracao/usuarios',
      );
      expect(NavLocation.paiDe('/patrimonios'), '/dashboard');
      expect(NavLocation.ehNivelSuperior('/configuracoes'), isTrue);
      expect(NavLocation.ehNivelSuperior('/patrimonios/novo'), isFalse);
    });
  });

  for (final largura in [320.0, 360.0, 390.0, 412.0]) {
    group('celular ${largura.toInt()} px (ADM, Android)', () {
      testWidgets('Início só selecionado em /dashboard; abas seguem a rota', (
        tester,
      ) async {
        final env = await _pump(tester, largura: largura);
        expect(env.path, '/dashboard');
        expect(_abaSelecionada(tester), NavTab.inicio.index);

        for (final aba in [NavTab.patrimonios, NavTab.movimentacoes]) {
          env.router.go(aba.rota);
          await tester.pumpAndSettle();
          expect(_abaSelecionada(tester), aba.index, reason: aba.rota);
        }
        // Setores saiu da barra: segue no menu lateral, sem barra inferior.
        env.router.go('/setores');
        await tester.pumpAndSettle();
        expect(_abaSelecionada(tester), isNull);
        expect(find.byType(InvTecBottomNav), findsNothing);
        expect(find.byIcon(Icons.menu), findsOneWidget);
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        expect(find.text('Setores'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'scanner pelo dashboard: aba Escanear e voltar ao dashboard',
        (tester) async {
          final env = await _pump(tester, largura: largura);
          await _push(tester, env, '/patrimonios/escanear');
          expect(env.path, '/patrimonios/escanear');
          expect(_abaSelecionada(tester), NavTab.escanear.index);
          expect(env.scanner.startCallCount, 1);

          await _voltarAndroid(tester);
          expect(env.path, '/dashboard');
          expect(_abaSelecionada(tester), NavTab.inicio.index);
          // Câmera liberada ao sair do scanner.
          expect(env.scanner.disposeCallCount, greaterThanOrEqualTo(1));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('Novo patrimônio: sem barra; seta e voltar levam à origem', (
        tester,
      ) async {
        final env = await _pump(tester, largura: largura);
        await _push(tester, env, '/patrimonios/novo');
        expect(find.byType(InvTecBottomNav), findsNothing);
        expect(find.byIcon(Icons.arrow_back), findsWidgets);

        await _voltarAndroid(tester); // formulário limpo: volta sem confirmar
        expect(env.path, '/dashboard');
        expect(_abaSelecionada(tester), NavTab.inicio.index);

        env.router.go('/patrimonios');
        await tester.pumpAndSettle();
        await _push(tester, env, '/patrimonios/novo');
        await tester.tap(find.byTooltip('Voltar').first);
        await tester.pumpAndSettle();
        expect(env.path, '/patrimonios');
        expect(_abaSelecionada(tester), NavTab.patrimonios.index);
      });

      testWidgets('detalhes voltam à tela anterior', (tester) async {
        final env = await _pump(tester, largura: largura);
        env.router.go('/patrimonios');
        await tester.pumpAndSettle();
        await _push(tester, env, '/patrimonios/qualquer-id');
        expect(find.byType(InvTecBottomNav), findsNothing);
        await _voltarAndroid(tester);
        expect(env.path, '/patrimonios');

        await _push(tester, env, '/movimentacoes/m1');
        expect(find.byType(InvTecBottomNav), findsNothing);
        await _voltarAndroid(tester);
        expect(env.path, '/patrimonios');
        expect(tester.takeException(), isNull);
      });

      testWidgets('tela interna sem pilha sobe ao pai; depois, ao Início', (
        tester,
      ) async {
        final env = await _pump(tester, largura: largura);
        env.router.go('/patrimonios/novo');
        await tester.pumpAndSettle();
        await _voltarAndroid(tester);
        expect(env.path, '/patrimonios');
        await _voltarAndroid(tester);
        expect(env.path, '/dashboard');
      });

      testWidgets('toques repetidos não duplicam rotas', (tester) async {
        final env = await _pump(tester, largura: largura);
        final barra = find.byType(InvTecBottomNav);
        for (var i = 0; i < 3; i++) {
          await tester.tap(
            find.descendant(of: barra, matching: find.text('Patrimônios')),
          );
          await tester.pumpAndSettle();
        }
        expect(env.path, '/patrimonios');
        expect(env.router.canPop(), isFalse);

        for (var i = 0; i < 2; i++) {
          await tester.tap(
            find.descendant(of: barra, matching: find.text('Escanear')),
          );
          await tester.pumpAndSettle();
        }
        expect(env.path, '/patrimonios/escanear');
        expect(env.router.canPop(), isFalse);

        // push de rota fixa já em exibição é ignorado.
        tester
            .element(find.byType(InvTecBottomNav))
            .pushUnico('/patrimonios/escanear');
        await tester.pumpAndSettle();
        expect(env.router.canPop(), isFalse);
      });

      testWidgets('Drawer: Configurações sem barra, menu no cabeçalho', (
        tester,
      ) async {
        final env = await _pump(tester, largura: largura);
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Configurações'));
        await tester.pumpAndSettle();
        expect(env.path, '/configuracoes');
        expect(find.byType(InvTecBottomNav), findsNothing);
        expect(find.byIcon(Icons.menu), findsOneWidget);

        await _voltarAndroid(tester);
        expect(env.path, '/dashboard');
        expect(_abaSelecionada(tester), NavTab.inicio.index);
      });

      testWidgets('teclado aberto esconde a barra', (tester) async {
        await _pump(tester, largura: largura);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(find.byType(InvTecBottomNav), findsNothing);
      });
    });
  }

  testWidgets('trocar de aba preserva a pesquisa de Patrimônios', (
    tester,
  ) async {
    final env = await _pump(tester);
    env.router.go('/patrimonios');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'notebook');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    env.router.go('/setores');
    await tester.pumpAndSettle();
    env.router.go('/patrimonios');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'notebook'), findsOneWidget);
  });

  group('perfis e sessão', () {
    for (final perfil in [ProfilePerfil.consulta, ProfilePerfil.gestor]) {
      testWidgets('${perfil.name}: sem Administração e sem acesso à rota', (
        tester,
      ) async {
        final env = await _pump(tester, perfil: perfil);
        env.router.go('/administracao/usuarios');
        await tester.pumpAndSettle();
        expect(env.path, '/dashboard');
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        expect(find.text('Administração'), findsNothing);
      });
    }

    testWidgets('ADM acessa Administração, que não tem aba', (tester) async {
      final env = await _pump(tester);
      env.router.go('/administracao/usuarios');
      await tester.pumpAndSettle();
      expect(env.path, '/administracao/usuarios');
      expect(find.byType(InvTecBottomNav), findsNothing);
    });

    testWidgets('logout leva ao login, sem barra e sem pilha', (tester) async {
      final env = await _pump(tester);
      await _push(tester, env, '/patrimonios/novo');
      env.router.go('/dashboard');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(env.path, '/login');
      expect(find.byType(InvTecBottomNav), findsNothing);
      expect(env.router.canPop(), isFalse);
    });
  });

  testWidgets('desktop: sem barra inferior e rota real em telas empilhadas', (
    tester,
  ) async {
    final env = await _pump(tester, largura: 1280, android: false);
    await _push(tester, env, '/patrimonios/novo');
    expect(find.byType(InvTecBottomNav), findsNothing);
    expect(env.path, '/patrimonios/novo');
  });
}
