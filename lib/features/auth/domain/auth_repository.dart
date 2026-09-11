import 'profile.dart';

abstract class AuthRepository {
  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  /// Id do usuário autenticado no Supabase Auth, ou nulo se não há sessão.
  String? get currentUserId;

  /// Busca o profile do usuário no banco. Respeita RLS: cada usuário sempre
  /// consegue ler a própria linha, mesmo com `ativo = false`.
  Future<Profile?> fetchProfile(String userId);

  /// Emite um evento sempre que o estado de autenticação do Supabase Auth
  /// mudar (login, logout, expiração/refresh de token).
  Stream<void> get authStateChanges;
}
