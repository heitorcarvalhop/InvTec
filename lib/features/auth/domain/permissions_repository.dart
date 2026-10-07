import 'permissao_efetiva.dart';

/// Acesso às permissões granulares de negócio (Etapa 3) — ver migrations
/// `20261006100000_add_permission_catalog.sql` e
/// `20261006110000_add_has_permission_and_override_rpcs.sql`. Não confundir
/// com `AuthRepository`/`private.has_perfil`: aquele resolve IDENTIDADE de
/// perfil (admin/gestor/operador/consulta) e o status de acesso da conta;
/// este resolve CAPACIDADE DE NEGÓCIO (perfil base + override individual).
abstract class PermissionsRepository {
  /// Chaves EFETIVAMENTE concedidas ao usuário autenticado (self-service,
  /// sem parâmetro). Conjunto vazio se a conta não estiver ACTIVE — nunca
  /// lança por esse motivo.
  Future<Set<String>> minhasPermissoes();

  /// ADMIN-only: visão completa (perfil base + override + efetiva) de todas
  /// as chaves do catálogo para um usuário específico.
  Future<List<PermissaoEfetiva>> obterPermissoesUsuario(String userId);

  /// ADMIN-only: cria/atualiza um override explícito (PERMITIR ou NEGAR,
  /// nunca um terceiro valor nulo) para `permissionKey` do usuário
  /// `userId`. Exige o alvo ACTIVE e nunca o próprio ADMIN que chama.
  Future<void> definirPermissaoUsuario({
    required String userId,
    required String permissionKey,
    required bool granted,
  });

  /// ADMIN-only: remove o override (se existir), voltando a herdar o
  /// padrão do perfil para esta chave.
  Future<void> removerOverridePermissaoUsuario({
    required String userId,
    required String permissionKey,
  });

  /// ADMIN-only: remove TODOS os overrides do usuário. Devolve quantos
  /// foram removidos.
  Future<int> resetarPermissoesUsuario(String userId);
}
