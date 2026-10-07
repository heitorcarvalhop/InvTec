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

  // Fonte única dos eventos "o profile mudou no servidor" — cada chamada a
  // [observeProfileChanges] ganha seu PRÓPRIO StreamController relayado a
  // partir desta fonte, mesmo padrão de
  // `FakeAppNotificationRepository._mudancasSource`: o cancelamento de UMA
  // chamada (ex.: logout, que cancela a subscription da sessão anterior) é
  // contável independentemente das demais — ver [cancelamentosCount].
  final _profileMudancasSource = StreamController<void>.broadcast();

  int signInCallCount = 0;
  int signOutCallCount = 0;
  int signUpCallCount = 0;
  int observeProfileChangesCallCount = 0;
  int reenviarSolicitacaoCallCount = 0;

  /// Se não-nulo, [reenviarSolicitacao] lança este erro em vez de completar
  /// com sucesso.
  Object? reenviarSolicitacaoError;

  /// Quantas vezes uma stream devolvida por [observeProfileChanges] foi
  /// cancelada — prova direta de que logout/troca de usuário não deixa uma
  /// assinatura "pendurada".
  int cancelamentosCount = 0;
  String? userIdObservado;

  /// Resultado devolvido pela próxima chamada a [signUp] — configurável por
  /// teste. Por padrão, simula sessão criada (login automático).
  AuthSignUpResult signUpResult = const AuthSignUpResult(sessaoCriada: true);

  /// Se não-nulo, [signUp] lança este erro em vez de completar com sucesso.
  Object? signUpError;

  @override
  String? get currentUserId => _userId;

  @override
  Future<Profile?> fetchProfile(String userId) async =>
      _profileResolver(userId);

  @override
  Future<AuthSignUpResult> signUp({
    required String nome,
    required String cpf,
    required String email,
    required String senha,
  }) async {
    signUpCallCount++;
    final erro = signUpError;
    if (erro != null) throw erro;
    return signUpResult;
  }

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
  Stream<void> observeProfileChanges(String userId) {
    observeProfileChangesCallCount++;
    userIdObservado = userId;

    late final StreamSubscription<void> relaySubscription;
    final controller = StreamController<void>.broadcast(
      onCancel: () {
        cancelamentosCount++;
        relaySubscription.cancel();
      },
    );
    relaySubscription = _profileMudancasSource.stream.listen(controller.add);

    return controller.stream;
  }

  /// SÓ PARA TESTE — simula um evento Realtime de mudança no profile
  /// chegando (ex.: ADMIN aprovou/rejeitou/bloqueou a conta observada).
  void emitirMudancaDeProfileParaTeste() => _profileMudancasSource.add(null);

  @override
  Future<void> reenviarSolicitacao() async {
    reenviarSolicitacaoCallCount++;
    final erro = reenviarSolicitacaoError;
    if (erro != null) throw erro;
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

  void dispose() {
    _authStateController.close();
    _profileMudancasSource.close();
  }
}
