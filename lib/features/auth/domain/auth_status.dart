import 'profile.dart';

/// Por que o InvTec negou a entrada mesmo com login válido no Supabase Auth.
/// `profileInactive` NÃO existe mais: perfil "inativo" hoje é um dos quatro
/// estados COM sessão (pending/rejected/blocked) — nunca mais um motivo de
/// logout forçado. O único caso que ainda força signOut é [profileNotFound].
enum AuthDenialReason { none, profileNotFound }

/// Os cinco estados de conta que o InvTec distingue na UI.
enum AuthAccountStatus { unauthenticated, pending, active, rejected, blocked }

/// Estado de autenticação resolvido pelo InvTec.
///
/// Ter sessão válida no Supabase Auth não é suficiente: também é preciso
/// saber em qual dos quatro estados de `access_status` o profile está — ver
/// [AuthController] em features/auth/presentation/auth_controller.dart.
/// `pending`/`rejected`/`blocked` continuam AUTENTICADOS (sessão viva, com
/// profile) — só `active` pode efetivamente operar o sistema
/// ([isAuthenticated]).
class AuthStatus {
  const AuthStatus._({
    required this.status,
    this.profile,
    this.denialReason = AuthDenialReason.none,
  });

  const AuthStatus.unauthenticated({AuthDenialReason denialReason = AuthDenialReason.none})
    : this._(status: AuthAccountStatus.unauthenticated, denialReason: denialReason);

  const AuthStatus.pending(Profile profile)
    : this._(status: AuthAccountStatus.pending, profile: profile);

  const AuthStatus.active(Profile profile)
    : this._(status: AuthAccountStatus.active, profile: profile);

  const AuthStatus.rejected(Profile profile)
    : this._(status: AuthAccountStatus.rejected, profile: profile);

  const AuthStatus.blocked(Profile profile)
    : this._(status: AuthAccountStatus.blocked, profile: profile);

  final AuthAccountStatus status;
  final Profile? profile;
  final AuthDenialReason denialReason;

  /// Só `true` para `active` — os demais estados têm sessão válida e
  /// `profile` preenchido, mas não podem operar o sistema de negócio.
  bool get isAuthenticated => status == AuthAccountStatus.active;
}
