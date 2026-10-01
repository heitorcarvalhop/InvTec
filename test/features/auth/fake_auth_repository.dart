import 'dart:async';

import 'package:invtec/features/auth/domain/auth_repository.dart';
import 'package:invtec/features/auth/domain/profile.dart';

/// Fake em memória de [AuthRepository], sem nenhuma chamada de rede — usado
/// para testar [AuthController] e widgets isoladamente do Supabase real.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    String? initialUserId,
    Profile? Function(String userId)? profileResolver,
  }) : _userId = initialUserId,
       _profileResolver = profileResolver ?? ((_) => null);

  String? _userId;
  final Profile? Function(String userId) _profileResolver;
  final _authStateController = StreamController<void>.broadcast();

  int signInCallCount = 0;
  int signOutCallCount = 0;

  @override
  String? get currentUserId => _userId;

  @override
  Future<Profile?> fetchProfile(String userId) async =>
      _profileResolver(userId);

  // Replay do estado atual a cada novo listener, como o ReplaySubject real
  // do gotrue faz em Supabase.auth.onAuthStateChange — importante para os
  // testes exercitarem o mesmo comportamento que causou o deadlock real
  // (ver AuthController.build).
  @override
  Stream<void> get authStateChanges async* {
    yield null;
    yield* _authStateController.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCallCount++;
    _userId = 'fake-user-id';
    _authStateController.add(null);
  }

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    _userId = null;
    _authStateController.add(null);
  }

  /// SÓ PARA TESTE — reemite um evento de
  /// `authStateChanges` SEM trocar [currentUserId]: simula um recomputo
  /// trivial da sessão (ex.: `AuthController` reagindo a um evento do
  /// gotrue que não é uma troca real de usuário) — usado para provar que
  /// dependentes de `authControllerProvider` não descartam estado só por
  /// causa de qualquer emissão, apenas quando o usuário resolvido muda de
  /// fato.
  void reemitirEstadoAtualParaTeste() => _authStateController.add(null);

  void dispose() => _authStateController.close();
}
