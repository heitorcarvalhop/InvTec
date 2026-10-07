import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/auth_status.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';

import 'fake_auth_repository.dart';

Profile _profile({
  required ProfileAccessStatus accessStatus,
  bool? ativo,
  int rejectionCount = 0,
}) {
  return Profile(
    id: 'fake-user-id',
    nome: 'Fulano de Tal',
    email: 'fulano@invtec.com',
    perfil: ProfilePerfil.admin,
    ativo: ativo ?? (accessStatus == ProfileAccessStatus.active),
    criadoEm: DateTime(2026, 1, 1),
    atualizadoEm: DateTime(2026, 1, 1),
    accessStatus: accessStatus,
    rejectionCount: rejectionCount,
  );
}

void main() {
  group('AuthController', () {
    test('sem sessão resolve para unauthenticated sem motivo', () async {
      final fake = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final status = await container.read(authControllerProvider.future);

      expect(status.isAuthenticated, isFalse);
      expect(status.status, AuthAccountStatus.unauthenticated);
      expect(status.denialReason, AuthDenialReason.none);
    });

    test('sessão com profile ACTIVE resolve para active (isAuthenticated)', () async {
      final fake = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(accessStatus: ProfileAccessStatus.active),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final status = await container.read(authControllerProvider.future);

      expect(status.isAuthenticated, isTrue);
      expect(status.status, AuthAccountStatus.active);
      expect(status.profile?.perfil, ProfilePerfil.admin);
      expect(fake.signOutCallCount, 0);
    });

    test(
      'sessão sem profile correspondente nega e encerra a sessão (único caso que força signOut)',
      () async {
        final fake = FakeAuthRepository(
          initialUserId: 'fake-user-id',
          profileResolver: (_) => null,
        );
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);
        addTearDown(fake.dispose);

        final status = await container.read(authControllerProvider.future);

        expect(status.isAuthenticated, isFalse);
        expect(status.status, AuthAccountStatus.unauthenticated);
        expect(status.denialReason, AuthDenialReason.profileNotFound);
        expect(fake.signOutCallCount, 1);
      },
    );

    for (final caso in [
      (ProfileAccessStatus.pending, AuthAccountStatus.pending),
      (ProfileAccessStatus.rejected, AuthAccountStatus.rejected),
      (ProfileAccessStatus.blocked, AuthAccountStatus.blocked),
    ]) {
      test(
        'profile ${caso.$1.value} permanece AUTENTICADO (sessão viva), sem signOut',
        () async {
          final fake = FakeAuthRepository(
            initialUserId: 'fake-user-id',
            profileResolver: (_) => _profile(accessStatus: caso.$1),
          );
          final container = ProviderContainer(
            overrides: [authRepositoryProvider.overrideWithValue(fake)],
          );
          addTearDown(container.dispose);
          addTearDown(fake.dispose);

          final status = await container.read(authControllerProvider.future);

          // "autenticado" aqui = tem sessão + profile, mas isAuthenticated
          // (que a UI usa para liberar o sistema de negócio) só é true para
          // ACTIVE.
          expect(status.status, caso.$2);
          expect(status.isAuthenticated, isFalse);
          expect(status.profile, isNotNull);
          expect(fake.signOutCallCount, 0);
        },
      );
    }

    test('signIn resolve para active após login bem-sucedido', () async {
      final fake = FakeAuthRepository(
        profileResolver: (_) => _profile(accessStatus: ProfileAccessStatus.active),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      // resolve o estado inicial (sem sessão) antes de logar
      await container.read(authControllerProvider.future);

      final completer = Completer<AuthStatus>();
      final subscription = container.listen(authControllerProvider, (
        previous,
        next,
      ) {
        final status = next.value;
        if (status != null && status.isAuthenticated && !completer.isCompleted) {
          completer.complete(status);
        }
      });
      addTearDown(subscription.close);

      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'admin@invtec.com', password: 'senha-correta');

      final status = await completer.future.timeout(const Duration(seconds: 2));

      expect(status.isAuthenticated, isTrue);
      expect(fake.signInCallCount, 1);
    });

    test('signOut resolve para unauthenticated', () async {
      final fake = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(accessStatus: ProfileAccessStatus.active),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      await container.read(authControllerProvider.future);

      final completer = Completer<AuthStatus>();
      final subscription = container.listen(authControllerProvider, (
        previous,
        next,
      ) {
        final status = next.value;
        if (status != null && !status.isAuthenticated && !completer.isCompleted) {
          completer.complete(status);
        }
      });
      addTearDown(subscription.close);

      await container.read(authControllerProvider.notifier).signOut();

      final status = await completer.future.timeout(const Duration(seconds: 2));

      expect(status.isAuthenticated, isFalse);
      expect(fake.signOutCallCount, 1);
    });

    test('abre observeProfileChanges com o id do profile em sessão', () async {
      final fake = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(accessStatus: ProfileAccessStatus.pending),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      await container.read(authControllerProvider.future);

      expect(fake.observeProfileChangesCallCount, 1);
      expect(fake.userIdObservado, 'fake-user-id');
    });

    test('nunca abre observeProfileChanges quando unauthenticated', () async {
      final fake = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      await container.read(authControllerProvider.future);

      expect(fake.observeProfileChangesCallCount, 0);
    });

    test('evento Realtime de mudança de profile (PENDING -> ACTIVE) recarrega o status', () async {
      var accessStatus = ProfileAccessStatus.pending;
      final fake = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(accessStatus: accessStatus),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final statusInicial = await container.read(authControllerProvider.future);
      expect(statusInicial.status, AuthAccountStatus.pending);

      // simula a aprovação chegando no servidor
      accessStatus = ProfileAccessStatus.active;

      final completer = Completer<AuthStatus>();
      final subscription = container.listen(authControllerProvider, (previous, next) {
        final status = next.value;
        if (status != null && status.status == AuthAccountStatus.active && !completer.isCompleted) {
          completer.complete(status);
        }
      });
      addTearDown(subscription.close);

      fake.emitirMudancaDeProfileParaTeste();

      final status = await completer.future.timeout(const Duration(seconds: 2));
      expect(status.isAuthenticated, isTrue);
    });

    test('atualizarStatus recarrega a partir do servidor (fallback manual)', () async {
      var accessStatus = ProfileAccessStatus.blocked;
      final fake = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(accessStatus: accessStatus),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final statusInicial = await container.read(authControllerProvider.future);
      expect(statusInicial.status, AuthAccountStatus.blocked);

      // o ADMIN desbloqueou no servidor, mas nenhum evento Realtime chegou
      // (ex.: conexão instável) — o botão "Atualizar status" chama
      // atualizarStatus() diretamente.
      accessStatus = ProfileAccessStatus.active;
      await container.read(authControllerProvider.notifier).atualizarStatus();

      final status = container.read(authControllerProvider).value;
      expect(status?.status, AuthAccountStatus.active);
    });

    test('logout cancela a subscription de observeProfileChanges anterior', () async {
      final fake = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(accessStatus: ProfileAccessStatus.active),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      await container.read(authControllerProvider.future);
      expect(fake.observeProfileChangesCallCount, 1);

      final completer = Completer<void>();
      final subscription = container.listen(authControllerProvider, (previous, next) {
        if ((next.value?.isAuthenticated ?? true) == false && !completer.isCompleted) {
          completer.complete();
        }
      });
      addTearDown(subscription.close);

      await container.read(authControllerProvider.notifier).signOut();
      await completer.future.timeout(const Duration(seconds: 2));

      // Prova DIRETA de que a subscription de observeProfileChanges da
      // sessão anterior foi cancelada (mesmo padrão de prova usado pela
      // NotificacoesController) — nunca fica "pendurada" após o logout.
      expect(fake.cancelamentosCount, 1);
    });
  });
}
