import '../../auth/domain/profile.dart';

/// Acesso administrativo a usuários (tela "Administração > Usuários").
///
/// Reaproveita o MESMO [Profile] usado pelo fluxo de autenticação — não
/// existe um "UserAdmin"/"AdminUser" separado: um usuário administrado é só
/// um [Profile] lido/alterado por quem está logado como ADMIN ACTIVE.
///
/// Não existe uma RPC dedicada de listagem (a Etapa 2 só abriu a policy
/// `profiles_select` para ADMIN ler todas as linhas via SELECT comum — ver
/// `supabase/migrations/20261005120000_add_profile_access_control.sql`,
/// seção 10) — por isso [listar] é implementada com um SELECT direto
/// filtrado no servidor, nunca uma RPC nova. As demais operações (aprovar/
/// rejeitar/bloquear/desbloquear/alterar identidade/alterar perfil) são
/// todas RPCs `SECURITY DEFINER` já existentes desde a Etapa 2 — ver
/// `supabase/migrations/20261005130000_add_admin_user_rpcs.sql`.
abstract class UsuarioAdminRepository {
  /// Lista usuários num único [status], com busca textual opcional por
  /// nome/e-mail/CPF (filtrada no servidor via `.or(...)`/`.ilike`). [busca]
  /// nulo ou vazio significa "sem filtro de texto".
  Future<List<Profile>> listar({
    required ProfileAccessStatus status,
    String? busca,
  });

  /// Um usuário específico, em qualquer `access_status`. Lança
  /// `AppException` (mensagem já traduzida) se não encontrado.
  Future<Profile> buscarPorId(String userId);

  /// Aprova uma solicitação PENDING, definindo o perfil final. Equivalente a
  /// `aprovar_usuario(p_user_id, p_perfil)`.
  Future<Profile> aprovar({required String userId, required ProfilePerfil perfil});

  /// Rejeita uma solicitação PENDING. A 3ª rejeição bloqueia automaticamente
  /// a conta — decisão do banco (`rejeitar_usuario`), não deste repositório.
  Future<Profile> rejeitar({required String userId, required String motivo});

  /// Bloqueia um usuário que não esteja já BLOCKED. Equivalente a
  /// `bloquear_usuario(p_user_id, p_motivo)`.
  Future<Profile> bloquear({required String userId, required String motivo});

  /// Desbloqueia um usuário BLOCKED — volta para ACTIVE (se já foi aprovado
  /// alguma vez) ou para PENDING com o contador de rejeições zerado (se
  /// nunca foi aprovado). Regra decidida pela RPC `desbloquear_usuario`.
  Future<Profile> desbloquear(String userId);

  /// Corrige nome/CPF de outro usuário. A RPC sempre exige a identidade
  /// completa resultante (nunca um campo parcial) e um motivo.
  Future<Profile> alterarIdentidade({
    required String userId,
    required String nome,
    required String cpf,
    required String motivo,
  });

  /// Troca o perfil (ADMIN/GESTOR/OPERADOR/CONSULTA) de um usuário.
  Future<Profile> alterarPerfil({required String userId, required ProfilePerfil perfil});
}
