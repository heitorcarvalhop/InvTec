import 'package:invtec/features/auth/domain/permissao_efetiva.dart';
import 'package:invtec/features/auth/domain/permissions_repository.dart';

/// Fake em memória de `PermissionsRepository` (feature `auth`, agente
/// auth-core) — sem Supabase real. Modela um catálogo fixo de chaves com um
/// padrão por perfil ([defaultDoPerfil]) e um mapa de overrides por usuário,
/// a MESMA semântica de 3 estados da RPC real (sem linha = herda o padrão;
/// `true`/`false` = override explícito) — ver
/// `supabase/migrations/20261006110000_add_has_permission_and_override_rpcs.sql`.
class FakePermissionsRepository implements PermissionsRepository {
  FakePermissionsRepository({Map<String, bool> defaults = const {}}) : _defaults = Map.of(defaults);

  final Map<String, bool> _defaults;

  /// `userId -> (permissionKey -> granted)`.
  final Map<String, Map<String, bool>> _overrides = {};

  int definirPermissaoCallCount = 0;
  int removerOverrideCallCount = 0;
  int resetarCallCount = 0;
  String? ultimoUserIdConsultado;

  /// SÓ PARA TESTE — define o override já existente de um usuário antes do
  /// controller carregar, sem passar pela RPC (monta o cenário inicial).
  void definirOverrideParaTeste(String userId, String permissionKey, bool granted) {
    (_overrides[userId] ??= {})[permissionKey] = granted;
  }

  @override
  Future<Set<String>> minhasPermissoes() async {
    return {for (final entry in _defaults.entries) if (entry.value) entry.key};
  }

  @override
  Future<List<PermissaoEfetiva>> obterPermissoesUsuario(String userId) async {
    ultimoUserIdConsultado = userId;
    final overridesDoUsuario = _overrides[userId] ?? const {};
    return [
      for (final entry in _defaults.entries)
        PermissaoEfetiva(
          permissionKey: entry.key,
          defaultDoPerfil: entry.value,
          override: overridesDoUsuario[entry.key],
          efetiva: overridesDoUsuario[entry.key] ?? entry.value,
        ),
    ];
  }

  @override
  Future<void> definirPermissaoUsuario({
    required String userId,
    required String permissionKey,
    required bool granted,
  }) async {
    definirPermissaoCallCount++;
    (_overrides[userId] ??= {})[permissionKey] = granted;
  }

  @override
  Future<void> removerOverridePermissaoUsuario({
    required String userId,
    required String permissionKey,
  }) async {
    removerOverrideCallCount++;
    _overrides[userId]?.remove(permissionKey);
  }

  @override
  Future<int> resetarPermissoesUsuario(String userId) async {
    resetarCallCount++;
    final overridesDoUsuario = _overrides[userId];
    final qtd = overridesDoUsuario?.length ?? 0;
    overridesDoUsuario?.clear();
    return qtd;
  }
}
