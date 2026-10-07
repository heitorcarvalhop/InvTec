/// Conjunto imutável das chaves de permissão EFETIVAMENTE concedidas ao
/// usuário atual (já resolvido perfil + override pelo servidor — ver
/// `minhas_permissoes` na migration
/// `20261006110000_add_has_permission_and_override_rpcs.sql`).
class CurrentPermissions {
  const CurrentPermissions(this._keys);

  const CurrentPermissions.vazio() : this(const {});

  final Set<String> _keys;

  bool hasPermission(String key) => _keys.contains(key);
}
