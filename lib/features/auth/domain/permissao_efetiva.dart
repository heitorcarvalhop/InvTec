/// Visão completa de UMA permissão para UM usuário — espelha a linha
/// devolvida por `obter_permissoes_usuario` (migration
/// `20261006110000_add_has_permission_and_override_rpcs.sql`): para cada
/// chave do catálogo, o padrão do perfil do alvo, o override (se existir —
/// `null` quando não há) e o valor EFETIVO resultante. Usada só pela futura
/// tela de administração de permissões (ADMIN).
class PermissaoEfetiva {
  const PermissaoEfetiva({
    required this.permissionKey,
    required this.defaultDoPerfil,
    required this.override,
    required this.efetiva,
  });

  factory PermissaoEfetiva.fromJson(Map<String, dynamic> json) {
    return PermissaoEfetiva(
      permissionKey: json['permission_key'] as String,
      defaultDoPerfil: json['default_do_perfil'] as bool,
      override: json['override'] as bool?,
      efetiva: json['efetiva'] as bool,
    );
  }

  final String permissionKey;
  final bool defaultDoPerfil;

  /// `null` = sem override (herda o padrão do perfil); `true`/`false` = o
  /// usuário tem um override explícito para esta chave.
  final bool? override;
  final bool efetiva;
}
