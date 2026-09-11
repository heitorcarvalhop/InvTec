import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/auth_status.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';

import 'fake_auth_repository.dart';

Profile _profile({required bool ativo}) {
  return Profile(
    id: 'fake-user-id',
    nome: 'Fulano de Tal',
    email: 'fulano@invtec.com',
    perfil: ProfilePerfil.admin,
    ativo: ativo,
    criadoEm: DateTime(2026, 1, 1),
    atualizadoEm: DateTime(2026, 1, 1),
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
      expect(status.denialReason, AuthDenialReason.none);
    });

    test('sessão com profile ativo resolve para authenticated', () async {
      final fake = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(ativo: true),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final status = await container.read(authControllerProvider.future);

      expect(status.isAuthenticated, isTrue);
      expect(status.profile?.perfil, ProfilePerfil.admin);
      expect(fake.signOutCallCount, 0);
    });

    test(
      'sessão sem profile correspondente nega e encerra a sessão',
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
        expect(status.denialReason, AuthDenialReason.profileNotFound);
        expect(fake.signOutCallCount, 1);
      },
    );

    test('profile inativo nega e encerra a sessão', () async {
      final fake = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(ativo: false),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final status = await container.read(authControllerProvider.future);

      expect(status.isAuthenticated, isFalse);
      expect(status.denialReason, AuthDenialReason.profileInactive);
      expect(fake.signOutCallCount, 1);
    });

    test('signIn resolve para authenticated após login bem-sucedido', () async {
      final fake = FakeAuthRepository(
        profileResolver: (_) => _profile(ativo: true),
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
        profileResolver: (_) => _profile(ativo: true),
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
  });
}
