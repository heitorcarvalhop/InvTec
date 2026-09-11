import 'profile.dart';

/// Por que o InvTec negou a entrada mesmo com login válido no Supabase Auth.
enum AuthDenialReason { none, profileNotFound, profileInactive }

/// Estado de autenticação resolvido pelo InvTec.
///
/// Ter sessão válida no Supabase Auth não é suficiente: também é preciso
/// existir um profile ativo — ver [AuthController] em
/// features/auth/presentation/auth_controller.dart.
class AuthStatus {
  const AuthStatus._({required this.profile, required this.denialReason});

  const AuthStatus.unauthenticated({
    AuthDenialReason denialReason = AuthDenialReason.none,
  }) : this._(profile: null, denialReason: denialReason);

  const AuthStatus.authenticated(Profile profile)
    : this._(profile: profile, denialReason: AuthDenialReason.none);

  final Profile? profile;
  final AuthDenialReason denialReason;

  bool get isAuthenticated => profile != null;
}
