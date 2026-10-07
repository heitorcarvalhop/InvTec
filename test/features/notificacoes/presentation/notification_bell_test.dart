import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/core/widgets/compact_icon_button.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/notificacoes/data/app_notification_repository_supabase.dart';
import 'package:invtec/features/notificacoes/domain/app_notification.dart';
import 'package:invtec/features/notificacoes/domain/app_notification_repository.dart';
import 'package:invtec/features/notificacoes/presentation/widgets/notification_bell.dart';

import '../../auth/fake_auth_repository.dart';
import '../fake_app_notification_repository.dart';

Profile _adminProfile() => Profile(
  id: 'fake-admin-id',
  nome: 'Heitor Pereira',
  email: 'heitor@invtec.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
  atualizadoEm: DateTime(2026, 1, 1),
  accessStatus: ProfileAccessStatus.active,
  rejectionCount: 0,
);

AppNotification _notificacao({
  String id = 'n1',
  String titulo = 'Nova solicitação de acesso',
  String corpo = 'João Silva solicitou acesso ao InvTec.',
  DateTime? lidaEm,
  DateTime? resolvidaEm,
  DateTime? criadaEm,
}) {
  return AppNotification(
    id: id,
    eventId: 'e-$id',
    tipo: TipoNotificacao.acessoSolicitado,
    titulo: titulo,
    corpo: corpo,
    alvoUsuarioId: 'joao-id',
    lidaEm: lidaEm,
    resolvidaEm: resolvidaEm,
    criadaEm: criadaEm ?? DateTime.now().subtract(const Duration(minutes: 2)),
  );
}

/// Mesmo motivo de `notification_panel_test.dart`: tocar numa notificação
/// de solicitação de acesso navega via `context.push` (seção 44), então o
/// teste precisa de um `GoRouter` real — não só `MaterialApp`.
GoRouter _routerDeTeste() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Center(child: NotificationBell())),
      ),
      GoRoute(
        path: '/administracao/usuarios/:id',
        builder: (context, state) => Scaffold(body: Text('Detalhe ${state.pathParameters['id']}')),
      ),
    ],
  );
}

/// Monta sino + fakes dentro de um app mínimo — o widget real
/// (`NotificacoesController`) decide o estado a partir do `profile` do
/// `FakeAuthRepository`, exatamente como em produção.
Future<(FakeAuthRepository, FakeAppNotificationRepository)> _pumpBell(
  WidgetTester tester, {
  List<AppNotification> notificacoes = const [],
  ThemeMode themeMode = ThemeMode.light,
  Size windowSize = const Size(1280, 800),
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-admin-id',
    profileResolver: (_) => _adminProfile(),
  );
  final fakeNotif = FakeAppNotificationRepository(notificacoes: notificacoes);
  addTearDown(fakeAuth.dispose);
  addTearDown(fakeNotif.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: _routerDeTeste(),
      ),
    ),
  );

  return (fakeAuth, fakeNotif);
}

void main() {
  group('NotificationBell', () {
    testWidgets('sem não lidas: sem badge e tooltip simples', (tester) async {
      await _pumpBell(tester, notificacoes: [_notificacao(lidaEm: DateTime(2026, 1, 1))]);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byIcon(Icons.notifications), findsNothing);
      expect(find.byTooltip('Notificações'), findsOneWidget);
    });

    testWidgets('com não lidas: mostra badge com a contagem e tooltip no singular/plural', (
      tester,
    ) async {
      await _pumpBell(tester, notificacoes: [_notificacao(id: 'n1')]);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip('Notificações, 1 não lida'), findsOneWidget);
    });

    testWidgets('badge mostra "99+" quando há 100 ou mais não lidas', (tester) async {
      final muitas = List.generate(100, (i) => _notificacao(id: 'n$i'));
      await _pumpBell(tester, notificacoes: muitas);
      await tester.pumpAndSettle();

      expect(find.text('99+'), findsOneWidget);
      expect(find.byTooltip('Notificações, 100 não lidas'), findsOneWidget);
    });

    testWidgets('abrir o painel mostra as notificações recentes', (tester) async {
      await _pumpBell(
        tester,
        notificacoes: [
          _notificacao(id: 'n1', titulo: 'Nova solicitação de acesso'),
          _notificacao(id: 'n2', titulo: 'Solicitação de acesso reenviada'),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CompactIconButton));
      await tester.pumpAndSettle();

      expect(find.text('Notificações'), findsOneWidget);
      expect(find.text('Nova solicitação de acesso'), findsOneWidget);
      expect(find.text('Solicitação de acesso reenviada'), findsOneWidget);
    });

    testWidgets('tocar numa notificação não lida chama marcarComoLida e navega para o usuário-alvo', (
      tester,
    ) async {
      final (_, fakeNotif) = await _pumpBell(tester, notificacoes: [_notificacao(id: 'n1')]);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CompactIconButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nova solicitação de acesso'));
      await tester.pumpAndSettle();

      expect(fakeNotif.marcarComoLidaCallCount, 1);
      // Navegou para o detalhe do usuário-alvo (`alvoUsuarioId` default
      // `joao-id` de `_notificacao`) — o popover fechou e a rota mudou.
      expect(find.text('Detalhe joao-id'), findsOneWidget);
    });

    testWidgets('marcar todas como lidas zera o badge', (tester) async {
      final (_, fakeNotif) = await _pumpBell(
        tester,
        notificacoes: [_notificacao(id: 'n1'), _notificacao(id: 'n2')],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CompactIconButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marcar todas como lidas'));
      await tester.pumpAndSettle();

      expect(fakeNotif.marcarTodasComoLidasCallCount, 1);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });

    testWidgets('funciona em dark mode sem exception', (tester) async {
      await _pumpBell(
        tester,
        notificacoes: [_notificacao(id: 'n1'), _notificacao(id: 'n2', resolvidaEm: DateTime(2026, 1, 2))],
        themeMode: ThemeMode.dark,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CompactIconButton));
      await tester.pumpAndSettle();

      expect(find.text('Notificações'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('estado de erro ao carregar não quebra o sino (sem badge, silencioso)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-admin-id',
        profileResolver: (_) => _adminProfile(),
      );
      addTearDown(fakeAuth.dispose);
      final fakeNotifQuebrado = _ThrowingAppNotificationRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            appNotificationRepositoryProvider.overrideWithValue(fakeNotifQuebrado),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: Center(child: NotificationBell())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sino aparece normal, sem badge — mesmo com o provider em erro.
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byTooltip('Notificações'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Repositório que sempre falha — só para o teste de resiliência do sino a
/// um `notificacoesControllerProvider` em `AsyncError` (ver
/// `NotificationBell`: loading/erro nunca travam ou assustam, é um recurso
/// secundário da topbar).
class _ThrowingAppNotificationRepository implements AppNotificationRepository {
  @override
  Future<List<AppNotification>> listarRecentes({int limite = 10}) {
    throw Exception('falha simulada');
  }

  @override
  Future<int> contarNaoLidas() {
    throw Exception('falha simulada');
  }

  @override
  Future<void> marcarComoLida(String id) {
    throw Exception('falha simulada');
  }

  @override
  Future<void> marcarTodasComoLidas() {
    throw Exception('falha simulada');
  }

  @override
  Stream<void> observarMudancas({required String destinatarioId}) => const Stream.empty();
}
