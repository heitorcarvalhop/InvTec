import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';
import 'package:invtec/features/notificacoes/data/app_notification_repository_supabase.dart';
import 'package:invtec/features/notificacoes/domain/app_notification.dart';
import 'package:invtec/features/notificacoes/presentation/notificacoes_controller.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_app_notification_repository.dart';

Profile _profile({
  required ProfilePerfil perfil,
  String id = 'fake-admin-id',
  ProfileAccessStatus accessStatus = ProfileAccessStatus.active,
}) {
  return Profile(
    id: id,
    nome: 'Fulano de Tal',
    email: 'fulano@invtec.com',
    perfil: perfil,
    ativo: accessStatus == ProfileAccessStatus.active,
    criadoEm: DateTime(2026, 1, 1),
    atualizadoEm: DateTime(2026, 1, 1),
    accessStatus: accessStatus,
    rejectionCount: 0,
  );
}

AppNotification _notificacao({
  String id = 'n1',
  String eventId = 'e1',
  DateTime? lidaEm,
  DateTime? resolvidaEm,
  DateTime? criadaEm,
}) {
  return AppNotification(
    id: id,
    eventId: eventId,
    tipo: TipoNotificacao.acessoSolicitado,
    titulo: 'Nova solicitação de acesso',
    corpo: 'João Silva solicitou acesso ao InvTec.',
    alvoUsuarioId: 'joao-id',
    lidaEm: lidaEm,
    resolvidaEm: resolvidaEm,
    criadaEm: criadaEm ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('NotificacoesController', () {
    test('usuário não-ADMIN resolve para estado vazio, sem observar mudanças', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.gestor),
      );
      final fakeNotif = FakeAppNotificationRepository(notificacoes: [_notificacao()]);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);
      addTearDown(fakeNotif.dispose);

      // Resolve authControllerProvider primeiro — mesmo padrão de
      // auth_controller_test.dart: evita a corrida entre o build() inicial
      // deste controller (que lê o auth ainda em loading) e a resolução
      // real do profile.
      await container.read(authControllerProvider.future);

      final estado = await container.read(notificacoesControllerProvider.future);

      expect(estado.recentes, isEmpty);
      expect(estado.naoLidas, 0);
      expect(fakeNotif.observarMudancasCallCount, 0);
    });

    test('ADMIN ativo carrega recentes e contagem de não lidas', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-admin-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.admin),
      );
      final fakeNotif = FakeAppNotificationRepository(
        notificacoes: [_notificacao(id: 'n1'), _notificacao(id: 'n2', lidaEm: DateTime(2026, 1, 2))],
      );
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);
      addTearDown(fakeNotif.dispose);

      // Resolve authControllerProvider primeiro — mesmo padrão de
      // auth_controller_test.dart: evita a corrida entre o build() inicial
      // deste controller (que lê o auth ainda em loading) e a resolução
      // real do profile.
      await container.read(authControllerProvider.future);

      final estado = await container.read(notificacoesControllerProvider.future);

      expect(estado.recentes, hasLength(2));
      expect(estado.naoLidas, 1);
      expect(fakeNotif.observarMudancasCallCount, 1);
      expect(fakeNotif.destinatarioIdObservado, 'fake-admin-id');
    });

    test('evento Realtime recarrega o estado automaticamente', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-admin-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.admin),
      );
      final fakeNotif = FakeAppNotificationRepository(notificacoes: [_notificacao()]);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);
      addTearDown(fakeNotif.dispose);

      // Resolve authControllerProvider primeiro — mesmo padrão de
      // auth_controller_test.dart: evita a corrida entre o build() inicial
      // deste controller (que lê o auth ainda em loading) e a resolução
      // real do profile.
      await container.read(authControllerProvider.future);

      await container.read(notificacoesControllerProvider.future);
      expect(container.read(notificacoesControllerProvider).value?.naoLidas, 1);

      // Uma segunda notificação "chega" no servidor; o evento Realtime
      // deve disparar um refresh que a traz para o estado.
      fakeNotif.adicionarParaTeste(_notificacao(id: 'n2', criadaEm: DateTime(2026, 1, 2)));

      final completer = Completer<int>();
      final subscription = container.listen(notificacoesControllerProvider, (previous, next) {
        final naoLidas = next.value?.naoLidas;
        if (naoLidas != null && naoLidas == 2 && !completer.isCompleted) {
          completer.complete(naoLidas);
        }
      });
      addTearDown(subscription.close);

      fakeNotif.emitirMudancaParaTeste();

      final naoLidas = await completer.future.timeout(const Duration(seconds: 2));
      expect(naoLidas, 2);
    });

    test('marcarComoLida chama o repositório e recarrega', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-admin-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.admin),
      );
      final fakeNotif = FakeAppNotificationRepository(notificacoes: [_notificacao(id: 'n1')]);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);
      addTearDown(fakeNotif.dispose);

      // Resolve authControllerProvider primeiro — mesmo padrão de
      // auth_controller_test.dart: evita a corrida entre o build() inicial
      // deste controller (que lê o auth ainda em loading) e a resolução
      // real do profile.
      await container.read(authControllerProvider.future);

      await container.read(notificacoesControllerProvider.future);
      expect(container.read(notificacoesControllerProvider).value?.naoLidas, 1);

      await container.read(notificacoesControllerProvider.notifier).marcarComoLida('n1');

      expect(fakeNotif.marcarComoLidaCallCount, 1);
      expect(container.read(notificacoesControllerProvider).value?.naoLidas, 0);
    });

    test('marcarTodasComoLidas chama o repositório e recarrega', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-admin-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.admin),
      );
      final fakeNotif = FakeAppNotificationRepository(
        notificacoes: [_notificacao(id: 'n1'), _notificacao(id: 'n2')],
      );
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);
      addTearDown(fakeNotif.dispose);

      // Resolve authControllerProvider primeiro — mesmo padrão de
      // auth_controller_test.dart: evita a corrida entre o build() inicial
      // deste controller (que lê o auth ainda em loading) e a resolução
      // real do profile.
      await container.read(authControllerProvider.future);

      await container.read(notificacoesControllerProvider.future);
      expect(container.read(notificacoesControllerProvider).value?.naoLidas, 2);

      await container.read(notificacoesControllerProvider.notifier).marcarTodasComoLidas();

      expect(fakeNotif.marcarTodasComoLidasCallCount, 1);
      expect(container.read(notificacoesControllerProvider).value?.naoLidas, 0);
    });

    test('logout cancela a subscription Realtime anterior', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-admin-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.admin),
      );
      final fakeNotif = FakeAppNotificationRepository(notificacoes: [_notificacao()]);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);
      addTearDown(fakeNotif.dispose);

      // Resolve authControllerProvider primeiro — mesmo padrão de
      // auth_controller_test.dart: evita a corrida entre o build() inicial
      // deste controller (que lê o auth ainda em loading) e a resolução
      // real do profile.
      await container.read(authControllerProvider.future);

      await container.read(notificacoesControllerProvider.future);
      expect(container.read(notificacoesControllerProvider).value?.naoLidas, 1);

      final completer = Completer<void>();
      final subscription = container.listen(notificacoesControllerProvider, (previous, next) {
        if ((next.value?.naoLidas ?? -1) == 0 && !completer.isCompleted) {
          completer.complete();
        }
      });
      addTearDown(subscription.close);

      await fakeAuth.signOut();

      await completer.future.timeout(const Duration(seconds: 2));
      expect(container.read(notificacoesControllerProvider).value?.recentes, isEmpty);

      // Prova DIRETA de que a subscription Realtime da sessão anterior foi
      // cancelada (não só que o estado mudou) — achado da revisão de QA:
      // sem isto, o teste provava só um efeito colateral, nunca o
      // cancelamento em si.
      expect(fakeNotif.cancelamentosCount, 1);
    });

    test('ADMIN bloqueado: estado esvazia e a subscription anterior é cancelada', () async {
      var statusAtual = ProfileAccessStatus.active;
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-admin-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.admin, accessStatus: statusAtual),
      );
      final fakeNotif = FakeAppNotificationRepository(notificacoes: [_notificacao()]);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          appNotificationRepositoryProvider.overrideWithValue(fakeNotif),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);
      addTearDown(fakeNotif.dispose);

      await container.read(authControllerProvider.future);

      final estado = await container.read(notificacoesControllerProvider.future);
      expect(estado.naoLidas, 1);
      expect(fakeNotif.observarMudancasCallCount, 1);

      // ADMIN é bloqueado (mesmo id, `perfil` continua ADMIN — só
      // `accessStatus` muda) — achado da revisão de QA: sem comparar
      // `status` além de `perfil`/`id`, este controller nunca invalidaria a
      // si mesmo aqui, deixando a assinatura Realtime de `notifications`
      // "pendurada" (sem efeito de segurança, já que a RLS já bloquearia a
      // leitura — mas uma inconsistência de lógica real).
      statusAtual = ProfileAccessStatus.blocked;
      fakeAuth.emitirMudancaDeProfileParaTeste();

      final completer = Completer<void>();
      final subscription = container.listen(notificacoesControllerProvider, (previous, next) {
        if ((next.value?.naoLidas ?? -1) == 0 && !completer.isCompleted) {
          completer.complete();
        }
      });
      addTearDown(subscription.close);

      await completer.future.timeout(const Duration(seconds: 2));

      expect(container.read(notificacoesControllerProvider).value?.recentes, isEmpty);
      // A subscription Realtime aberta enquanto ainda era ADMIN ACTIVE foi
      // cancelada — prova direta, não só o efeito colateral do estado vazio.
      expect(fakeNotif.cancelamentosCount, 1);
    });
  });
}
