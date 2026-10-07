import 'profile.dart';

/// Resultado de [AuthRepository.signUp]. `sessaoCriada=true` quando o
/// Supabase já devolve sessão ativa (login automático); `false` quando exige
/// confirmação de e-mail antes de liberar a sessão.
class AuthSignUpResult {
  const AuthSignUpResult({required this.sessaoCriada});

  final bool sessaoCriada;
}

abstract class AuthRepository {
  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  /// Cria a conta no Supabase Auth. A assinatura TIPADA (nunca um Map
  /// arbitrário) é deliberada: nome/cpf são os ÚNICOS dados de identidade
  /// aceitos — não existe caminho para o caller injetar `perfil`/`ativo`/
  /// `access_status`/qualquer chave de privilégio na metadata enviada ao
  /// Supabase (ver `AuthRepositorySupabase.signUp` e `handle_new_user` no
  /// banco, que também ignora essas chaves mesmo se chegassem).
  Future<AuthSignUpResult> signUp({
    required String nome,
    required String cpf,
    required String email,
    required String senha,
  });

  /// Id do usuário autenticado no Supabase Auth, ou nulo se não há sessão.
  String? get currentUserId;

  /// Busca o profile do usuário no banco. Respeita RLS: cada usuário sempre
  /// consegue ler a própria linha, seja qual for o `access_status`.
  Future<Profile?> fetchProfile(String userId);

  /// Emite um evento sempre que o estado de autenticação do Supabase Auth
  /// mudar (login, logout, expiração/refresh de token).
  Stream<void> get authStateChanges;

  /// Emite um evento sempre que a PRÓPRIA linha de `profiles` do usuário
  /// muda no servidor (ex.: aprovação/rejeição/bloqueio por um ADMIN) —
  /// usado por [AuthController] para recarregar o status sem depender só de
  /// o usuário atualizar a página manualmente.
  Stream<void> observeProfileChanges(String userId);

  /// Ação self-service do próprio usuário REJECTED (nunca uma ação
  /// administrativa) — chama a RPC `reenviar_solicitacao_acesso`, que
  /// recoloca a conta em PENDING para nova análise. Não devolve o profile
  /// atualizado: quem chama confia no Realtime/`atualizarStatus()` de
  /// [AuthController] para refletir a mudança, mesmo padrão dos demais
  /// métodos deste repositório.
  Future<void> reenviarSolicitacao();
}
