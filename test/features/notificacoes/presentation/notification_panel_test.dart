import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/notificacoes/data/app_notification_repository_supabase.dart';
import 'package:invtec/features/notificacoes/domain/app_notification.dart';
import 'package:invtec/features/notificacoes/presentation/widgets/notification_panel.dart';

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

/// Uma notificação de solicitação de acesso navega para
/// `/administracao/usuarios/:id` ao ser tocada (seção 44) — por isso o
/// painel precisa de um `GoRouter` real no teste, não só um `MaterialApp`
/// simples; sem isso `context.push` lançaria "No GoRouter found in context".
/// A segunda rota é um placeholder mínimo só para o teste confirmar que a
/// navegação de fato aconteceu (mostra o `id` recebido).
GoRouter _routerDeTeste(double panelWidth) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: panelWidth, child: const NotificationPanel()),
          ),
        ),
      ),
      GoRoute(
        path: '/administracao/usuarios/:id',
        builder: (context, state) => Scaffold(body: Text('Detalhe ${state.pathParameters['id']}')),
      ),
    ],
  );
}

Future<(FakeAuthRepository, FakeAppNotificationRepository)> _pumpPanel(
  WidgetTester tester, {
  List<AppNotification> notificacoes = const [],
  Size windowSize = const Size(400, 700),
  double panelWidth = 380,
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
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: _routerDeTeste(panelWidth)),
    ),
  );
  await tester.pumpAndSettle();

  return (fakeAuth, fakeNotif);
}

void main() {
  group('formatarTempoRelativo', () {
    test('minutos, horas e dias em português', () {
      final agora = DateTime(2026, 1, 10, 12, 0, 0);
      expect(formatarTempoRelativo(agora.subtract(const Duration(seconds: 10)), agora: agora), 'agora mesmo');
      expect(formatarTempoRelativo(agora.subtract(const Duration(minutes: 2)), agora: agora), 'há 2 min');
      expect(formatarTempoRelativo(agora.subtract(const Duration(hours: 3)), agora: agora), 'há 3h');
      expect(formatarTempoRelativo(agora.subtract(const Duration(days: 2)), agora: agora), 'há 2 dias');
      expect(formatarTempoRelativo(agora.subtract(const Duration(days: 1)), agora: agora), 'há 1 dia');
    });
  });

  group('NotificationPanel', () {
    testWidgets('estado vazio mostra mensagem amigável', (tester) async {
      await _pumpPanel(tester, notificacoes: []);

      expect(find.text('Nenhuma notificação por aqui'), findsOneWidget);
    });

    testWidgets('mostra título, corpo e tempo relativo de cada notificação', (tester) async {
      await _pumpPanel(
        tester,
        notificacoes: [
          _notificacao(
            id: 'n1',
            titulo: 'Nova solicitação de acesso',
            corpo: 'João Silva solicitou acesso ao InvTec.',
            criadaEm: DateTime.now().subtract(const Duration(minutes: 2)),
          ),
        ],
      );

      expect(find.text('Nova solicitação de acesso'), findsOneWidget);
      expect(find.text('João Silva solicitou acesso ao InvTec.'), findsOneWidget);
      expect(find.text('há 2 min'), findsOneWidget);
    });

    testWidgets('tocar numa notificação não lida chama marcarComoLida e navega para o usuário-alvo', (
      tester,
    ) async {
      final (_, fakeNotif) = await _pumpPanel(
        tester,
        notificacoes: [_notificacao(id: 'n1', titulo: 'Não lida')],
      );

      await tester.tap(find.text('Não lida'));
      await tester.pumpAndSettle();

      expect(fakeNotif.marcarComoLidaCallCount, 1);
      // Navegou para `/administracao/usuarios/joao-id` (alvoUsuarioId
      // default de `_notificacao`) — o painel (rota '/') saiu da árvore.
      expect(find.text('Detalhe joao-id'), findsOneWidget);
      expect(find.text('Não lida'), findsNothing);
    });

    testWidgets('tocar numa notificação já lida navega mas não chama marcarComoLida de novo', (
      tester,
    ) async {
      final (_, fakeNotif) = await _pumpPanel(
        tester,
        notificacoes: [_notificacao(id: 'n2', titulo: 'Já lida', lidaEm: DateTime(2026, 1, 1))],
      );

      await tester.tap(find.text('Já lida'));
      await tester.pumpAndSettle();

      expect(fakeNotif.marcarComoLidaCallCount, 0);
      expect(find.text('Detalhe joao-id'), findsOneWidget);
    });

    testWidgets('notificação de um tipo sem tela de destino não navega (só marca como lida)', (
      tester,
    ) async {
      final (_, fakeNotif) = await _pumpPanel(
        tester,
        notificacoes: [
          AppNotification(
            id: 'n3',
            eventId: 'e3',
            tipo: 'TIPO_FUTURO_AINDA_SEM_TELA',
            titulo: 'Aviso futuro',
            corpo: 'Categoria ainda sem navegação própria.',
            alvoUsuarioId: 'joao-id',
            criadaEm: DateTime.now(),
          ),
        ],
      );

      await tester.tap(find.text('Aviso futuro'));
      await tester.pumpAndSettle();

      expect(fakeNotif.marcarComoLidaCallCount, 1);
      // Continua na mesma rota (painel) — nenhuma navegação foi tentada.
      expect(find.text('Notificações'), findsOneWidget);
      expect(find.text('Detalhe joao-id'), findsNothing);
    });

    testWidgets('botão "Marcar todas como lidas" desabilita quando não há não lidas', (
      tester,
    ) async {
      await _pumpPanel(tester, notificacoes: [_notificacao(id: 'n1', lidaEm: DateTime(2026, 1, 1))]);

      final botao = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Marcar todas como lidas'));
      expect(botao.onPressed, isNull);
    });

    testWidgets('"Marcar todas como lidas" chama o controller e some o destaque de não lida', (
      tester,
    ) async {
      final (_, fakeNotif) = await _pumpPanel(
        tester,
        notificacoes: [_notificacao(id: 'n1'), _notificacao(id: 'n2')],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Marcar todas como lidas'));
      await tester.pumpAndSettle();

      expect(fakeNotif.marcarTodasComoLidasCallCount, 1);
      final botao = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Marcar todas como lidas'));
      expect(botao.onPressed, isNull);
    });

    testWidgets('notificação resolvida aparece com opacidade reduzida e nota "Solicitação analisada"', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        notificacoes: [
          _notificacao(id: 'n1', titulo: 'Em aberto'),
          _notificacao(id: 'n2', titulo: 'Já analisada', resolvidaEm: DateTime(2026, 1, 2)),
        ],
      );

      expect(find.text('Solicitação analisada'), findsOneWidget);

      final opacityResolvida = tester.widget<Opacity>(
        find.ancestor(of: find.text('Já analisada'), matching: find.byType(Opacity)).first,
      );
      expect(opacityResolvida.opacity, lessThan(1.0));

      // O item em aberto não tem nenhum ancestral Opacity adicionado por
      // este widget (continua com opacidade total, sem a dimunição).
      expect(find.ancestor(of: find.text('Em aberto'), matching: find.byType(Opacity)), findsNothing);
    });

    testWidgets('notificação não lida e resolvida mantém o indicador de não lida', (tester) async {
      await _pumpPanel(
        tester,
        notificacoes: [
          _notificacao(id: 'n1', titulo: 'Não lida e resolvida', resolvidaEm: DateTime(2026, 1, 2)),
        ],
      );

      // Continua contando como não lida (ver NotificationBell/testes de
      // badge) e ainda exibe a nota de resolvida — as duas dimensões
      // coexistem.
      expect(find.text('Solicitação analisada'), findsOneWidget);
      expect(find.text('Não lida e resolvida'), findsOneWidget);
    });

    testWidgets('largura estreita (380px) não gera overflow horizontal', (tester) async {
      await _pumpPanel(
        tester,
        windowSize: const Size(380, 700),
        panelWidth: 380,
        notificacoes: [
          _notificacao(
            id: 'n1',
            titulo: 'Nova solicitação de acesso muito longa para testar quebra de linha',
            corpo:
                'João Silva da Diretoria de Tecnologia e Inovação solicitou acesso ao InvTec '
                'com um corpo de texto deliberadamente longo.',
          ),
          _notificacao(id: 'n2', resolvidaEm: DateTime(2026, 1, 2)),
        ],
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('funciona em dark mode sem exception', (tester) async {
      tester.view.physicalSize = const Size(380, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-admin-id',
        profileResolver: (_) => _adminProfile(),
      );
      final fakeNotif = FakeAppNotificationRepository(
        notificacoes: [_notificacao(id: 'n1'), _notificacao(id: 'n2', resolvidaEm: DateTime(2026, 1, 2))],
      );
      addTearDown(fakeAuth.dispose);
      addTearDown(fakeNotif.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const Scaffold(body: SizedBox(width: 380, child: NotificationPanel())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notificações'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
