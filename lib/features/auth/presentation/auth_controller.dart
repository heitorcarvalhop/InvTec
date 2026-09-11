import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository_supabase.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_status.dart';

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthStatus>(
  AuthController.new,
);

/// Fonte única de verdade sobre "o usuário pode usar o InvTec agora?".
///
/// Ter sessão válida no Supabase Auth não é suficiente: também é preciso
/// existir um profile com `ativo = true` (ver docs/database.md). Reage
/// automaticamente a login/logout/expiração de sessão via
/// [AuthRepository.authStateChanges] — inclusive à sessão já existente
/// quando o app é reaberto, já restaurada pelo supabase_flutter antes de
/// [build] rodar pela primeira vez.
///
/// Não é a autoridade de segurança do sistema: apenas decide o que mostrar
/// na interface. RLS e as RPCs no Postgres continuam sendo a autoridade
/// final — ver docs/database.md.
class AuthController extends AsyncNotifier<AuthStatus> {
  StreamSubscription<void>? _subscription;

  @override
  Future<AuthStatus> build() async {
    final repository = ref.watch(authRepositoryProvider);

    // O stream do Supabase reenvia (replay) o estado atual para todo novo
    // listener assim que ele se inscreve — inclusive este, ainda dentro do
    // próprio build(). Reagir a esse primeiro evento chamaria
    // invalidateSelf() enquanto build() ainda está resolvendo, o que trava
    // o AsyncNotifier. Ele é redundante mesmo: build() já está calculando
    // esse mesmo estado atual logo abaixo. Só o ignoramos; eventos
    // seguintes (login/logout reais) continuam disparando invalidateSelf().
    var isReplayedEvent = true;
    _subscription = repository.authStateChanges.listen((_) {
      if (isReplayedEvent) {
        isReplayedEvent = false;
        return;
      }
      ref.invalidateSelf();
    });
    ref.onDispose(() => _subscription?.cancel());

    return _resolveStatus(repository);
  }

  Future<AuthStatus> _resolveStatus(AuthRepository repository) async {
    final userId = repository.currentUserId;
    if (userId == null) {
      return const AuthStatus.unauthenticated();
    }

    final profile = await repository.fetchProfile(userId);
    if (profile == null) {
      _forceSignOut(repository);
      return const AuthStatus.unauthenticated(
        denialReason: AuthDenialReason.profileNotFound,
      );
    }
    if (!profile.ativo) {
      _forceSignOut(repository);
      return const AuthStatus.unauthenticated(
        denialReason: AuthDenialReason.profileInactive,
      );
    }

    return AuthStatus.authenticated(profile);
  }

  /// Efetua o signOut sem esperar por ele (fire-and-forget) — de propósito.
  /// Se fizéssemos `await` aqui, o evento de authStateChanges disparado pelo
  /// próprio signOut invalidaria este provider enquanto [build] ainda está
  /// em execução, travando o AsyncNotifier. Como este método só é chamado
  /// depois que já sabemos o motivo da negação (perfil inexistente/inativo),
  /// o [build] pode retornar o status correto imediatamente; o signOut
  /// termina de forma assíncrona e independente.
  void _forceSignOut(AuthRepository repository) {
    unawaited(repository.signOut().catchError((_) {}));
  }

  Future<void> signIn({required String email, required String password}) {
    return ref
        .read(authRepositoryProvider)
        .signIn(email: email, password: password);
  }

  Future<void> signOut() {
    return ref.read(authRepositoryProvider).signOut();
  }
}
