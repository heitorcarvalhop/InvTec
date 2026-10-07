import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository_supabase.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_status.dart';
import '../domain/profile.dart';

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthStatus>(
  AuthController.new,
);

/// Fonte única de verdade sobre "em que estado de conta o usuário está
/// agora?". Ter sessão válida no Supabase Auth não é suficiente: também é
/// preciso saber o `access_status` do profile (PENDING/ACTIVE/REJECTED/
/// BLOCKED — ver docs/database.md). Reage automaticamente a login/logout/
/// expiração de sessão via [AuthRepository.authStateChanges] — inclusive à
/// sessão já existente quando o app é reaberto, já restaurada pelo
/// supabase_flutter antes de [build] rodar pela primeira vez — e a mudanças
/// no PRÓPRIO profile em sessão (aprovação/rejeição/bloqueio por um ADMIN)
/// via [AuthRepository.observeProfileChanges].
///
/// Não é a autoridade de segurança do sistema: apenas decide o que mostrar
/// na interface. RLS e as RPCs no Postgres continuam sendo a autoridade
/// final — ver docs/database.md.
class AuthController extends AsyncNotifier<AuthStatus> {
  StreamSubscription<void>? _authSubscription;
  StreamSubscription<void>? _profileSubscription;

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
    _authSubscription = repository.authStateChanges.listen((_) {
      if (isReplayedEvent) {
        isReplayedEvent = false;
        return;
      }
      ref.invalidateSelf();
    });
    ref.onDispose(() {
      _authSubscription?.cancel();
      _profileSubscription?.cancel();
    });

    final status = await _resolveStatus(repository);

    // Realtime de status em sessão (PENDING/ACTIVE/REJECTED/BLOCKED): só
    // faz sentido com um userId resolvido — nunca abrimos esta subscription
    // para `unauthenticated` (profile null, sem id para filtrar). Fallback
    // explícito: o Realtime só dispara um refresh — `atualizarStatus()`
    // (chamado pela UI, ex. botão "Atualizar status" nas telas PENDING/
    // BLOCKED) sempre busca o estado atual do servidor, nunca depende só de
    // um evento já ter chegado.
    final profile = status.profile;
    if (profile != null) {
      _profileSubscription = repository.observeProfileChanges(profile.id).listen((_) {
        ref.invalidateSelf();
      });
    }

    return status;
  }

  Future<AuthStatus> _resolveStatus(AuthRepository repository) async {
    final userId = repository.currentUserId;
    if (userId == null) {
      return const AuthStatus.unauthenticated();
    }

    final profile = await repository.fetchProfile(userId);
    if (profile == null) {
      // Nunca deveria acontecer na prática (handle_new_user sempre cria o
      // profile na mesma transação do signup) — tratado defensivamente.
      // Único caso que ainda força signOut: sem profile não há NENHUM dos
      // quatro estados de conta para mostrar.
      _forceSignOut(repository);
      return const AuthStatus.unauthenticated(
        denialReason: AuthDenialReason.profileNotFound,
      );
    }

    // Nunca inferir estado a partir de `ativo` isoladamente — só de
    // `accessStatus` (o banco garante que os dois são coerentes, mas
    // `accessStatus` é a fonte de verdade semântica). PENDING/REJECTED/
    // BLOCKED permanecem AUTENTICADOS (sessão viva) — nenhum dos três força
    // signOut.
    switch (profile.accessStatus) {
      case ProfileAccessStatus.pending:
        return AuthStatus.pending(profile);
      case ProfileAccessStatus.active:
        return AuthStatus.active(profile);
      case ProfileAccessStatus.rejected:
        return AuthStatus.rejected(profile);
      case ProfileAccessStatus.blocked:
        return AuthStatus.blocked(profile);
    }
  }

  /// Efetua o signOut sem esperar por ele (fire-and-forget) — de propósito.
  /// Se fizéssemos `await` aqui, o evento de authStateChanges disparado pelo
  /// próprio signOut invalidaria este provider enquanto [build] ainda está
  /// em execução, travando o AsyncNotifier. Como este método só é chamado
  /// depois que já sabemos o motivo da negação (profile inexistente), o
  /// [build] pode retornar o status correto imediatamente; o signOut
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

  /// Recarrega o status a partir do servidor — fallback manual para quando
  /// o Realtime não chega (evento perdido, conexão instável). As telas
  /// PENDING/BLOCKED expõem um botão "Atualizar status" que chama este
  /// método.
  Future<void> atualizarStatus() {
    ref.invalidateSelf();
    return future;
  }
}
