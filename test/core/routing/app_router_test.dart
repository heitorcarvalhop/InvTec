import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/app/app.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/permissao_efetiva.dart';
import 'package:invtec/features/auth/domain/permissions_repository.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/notificacoes/data/app_notification_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';

import '../../features/auth/fake_auth_repository.dart';
import '../../features/dashboard/fake_dashboard_repository.dart';
import '../../features/notificacoes/fake_app_notification_repository.dart';
import '../../features/patrimonios/fake_patrimonio_repository.dart';
import '../../features/patrimonios/fake_tipo_patrimonio_repository.dart';
import '../../features/setores/fake_setor_repository.dart';

/// Fake mínimo — nenhum teste aqui exercita permissões granulares em si
/// (isso é `current_permissions_controller_test.dart`); só evita que
/// páginas de negócio (que já chamam `ref.hasPermission`) tentem acessar
/// `Supabase.instance.client` real durante o pump.
class _FakePermissionsRepository implements PermissionsRepository {
  @override
  Future<Set<String>> minhasPermissoes() async => const {};

  @override
  Future<List<PermissaoEfetiva>> obterPermissoesUsuario(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> definirPermissaoUsuario({
    required String userId,
    required String permissionKey,
    required bool granted,
  }) => throw UnimplementedError();

  @override
  Future<void> removerOverridePermissaoUsuario({
    required String userId,
    required String permissionKey,
  }) => throw UnimplementedError();

  @override
  Future<int> resetarPermissoesUsuario(String userId) =>
      throw UnimplementedError();
}

Profile _profile({
  required ProfileAccessStatus accessStatus,
  ProfilePerfil perfil = ProfilePerfil.operador,
}) {
  return Profile(
    id: 'fake-user-id',
    nome: 'Usuária de Teste',
    email: 'teste@invtec.com',
    perfil: perfil,
    ativo: accessStatus == ProfileAccessStatus.active,
    criadoEm: DateTime.utc(2026, 1, 1),
    atualizadoEm: DateTime.utc(2026, 1, 1),
    accessStatus: accessStatus,
    rejectionCount: 0,
  );
}

Future<FakeAuthRepository> _pump(
  WidgetTester tester, {
  String? initialUserId,
  Profile? Function(String userId)? profileResolver,
}) async {
  final fakeAuth = FakeAuthRepository(
    initialUserId: initialUserId,
    profileResolver: profileResolver,
  );
  addTearDown(fakeAuth.dispose);

  // Janela explicitamente "desktop" (>= 1024 lógicos — ver
  // lib/core/responsive/breakpoints.dart), mesmo padrão de
  // test/core/shell/app_shell_test.dart. Sem isto, o tamanho padrão do
  // flutter_test (800x600 lógicos) cai na faixa "tablet", onde a sidebar
  // nasce RECOLHIDA por padrão (AppShell: `sidebarRecolhida = preferenciaSalva
  // ?? (screenSize == ScreenSize.tablet)`) — e a marca "InvTec" só é
  // desenhada quando a sidebar está expandida (NavigationSidebar), nunca na
  // topbar do desktop/tablet (só a AppBar do mobile mostra "InvTec").
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        permissionsRepositoryProvider.overrideWithValue(
          _FakePermissionsRepository(),
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

  return fakeAuth;
}

void main() {
  group('Redirect centralizado do GoRouter (Etapa 5)', () {
    testWidgets('unauthenticated abre em /login', (tester) async {
      await _pump(tester);

      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
    });

    testWidgets('PENDING é redirecionado para a tela de acesso pendente', (
      tester,
    ) async {
      await _pump(
        tester,
        initialUserId: 'fake-user-id',
        profileResolver: (_) =>
            _profile(accessStatus: ProfileAccessStatus.pending),
      );

      // Título real de AcessoPendentePage (lib/features/auth/presentation/
      // acesso_pendente_page.dart) — o "TODO: ..." era um placeholder
      // temporário do auth-core, já substituído pela tela real do design-ui.
      expect(find.text('Solicitação enviada'), findsOneWidget);
      // nunca cai no dashboard/login enquanto PENDING
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsNothing);
    });

    testWidgets('REJECTED é redirecionado para a tela de acesso rejeitado', (
      tester,
    ) async {
      await _pump(
        tester,
        initialUserId: 'fake-user-id',
        profileResolver: (_) =>
            _profile(accessStatus: ProfileAccessStatus.rejected),
      );

      // Título real de AcessoRejeitadoPage.
      expect(find.text('Solicitação não aprovada'), findsOneWidget);
    });

    testWidgets('BLOCKED é redirecionado para a tela de acesso bloqueado', (
      tester,
    ) async {
      await _pump(
        tester,
        initialUserId: 'fake-user-id',
        profileResolver: (_) =>
            _profile(accessStatus: ProfileAccessStatus.blocked),
      );

      // Título real de AcessoBloqueadoPage.
      expect(find.text('Acesso bloqueado'), findsOneWidget);
    });

    testWidgets('ACTIVE entra normalmente no app (dashboard)', (tester) async {
      await _pump(
        tester,
        initialUserId: 'fake-user-id',
        profileResolver: (_) =>
            _profile(accessStatus: ProfileAccessStatus.active),
      );

      // "InvTec" só é desenhado na sidebar expandida (AppShell, janela
      // desktop — ver _pump) — nunca na topbar do desktop/tablet.
      expect(find.text('InvTec'), findsOneWidget);
      expect(find.text('Solicitação enviada'), findsNothing);
    });

    testWidgets(
      'ACTIVE não-ADMIN tentando /administracao/usuarios é negado (fica no dashboard)',
      (tester) async {
        await _pump(
          tester,
          initialUserId: 'fake-user-id',
          profileResolver: (_) => _profile(
            accessStatus: ProfileAccessStatus.active,
            perfil: ProfilePerfil.operador,
          ),
        );

        // Navegação direta por código (equivalente a digitar a URL) — o
        // redirect central precisa negar mesmo assim, não só esconder o item
        // "Administração" da sidebar.
        //
        // `tester.element(find.byType(MaterialApp))` captura o elemento do
        // PRÓPRIO `MaterialApp.router` — isso fica ACIMA/fora de onde o
        // `Router`/`InheritedGoRouter` é provido na árvore (`GoRouter.of`
        // procura um ANCESTRAL `InheritedGoRouter`, e o `MaterialApp` é quem
        // cria esse `Router`, não é descendente dele) — daí o "No GoRouter
        // found in context". Em vez disso, captura-se o `GoRouter` a partir de
        // um `Scaffold` (sempre presente dentro do `AppShell`, descendente do
        // `Router`) e guarda-se a INSTÂNCIA (não o `BuildContext`, que fica
        // potencialmente desmontado depois da navegação) para a asserção final.
        final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
        router.go('/administracao/usuarios');
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/dashboard',
        );
      },
    );

    testWidgets('ACTIVE ADMIN acessando /administracao/usuarios é permitido', (
      tester,
    ) async {
      await _pump(
        tester,
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(
          accessStatus: ProfileAccessStatus.active,
          perfil: ProfilePerfil.admin,
        ),
      );

      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go('/administracao/usuarios');
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/administracao/usuarios',
      );
    });

    testWidgets(
      'ACTIVE tentando /login ou /cadastro é redirecionado para /dashboard',
      (tester) async {
        await _pump(
          tester,
          initialUserId: 'fake-user-id',
          profileResolver: (_) =>
              _profile(accessStatus: ProfileAccessStatus.active),
        );

        final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
        router.go('/login');
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/dashboard',
        );
      },
    );
  });
}
