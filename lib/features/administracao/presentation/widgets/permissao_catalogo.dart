/// Catálogo de permissões para fins de APRESENTAÇÃO (rótulo PT-BR + módulo
/// de agrupamento) — a lista REAL de chaves válidas vive no banco
/// (`public.permissions`, migration
/// `20261006100000_add_permission_catalog.sql`) e chega pronta em
/// `AdminUsuarioDetalheState.permissoes`; este catálogo client-side só serve
/// para ORDENAR/AGRUPAR/rotular o que já veio do servidor — nunca decide
/// quais chaves existem. Se uma chave desconhecida aparecer (nova permissão
/// lançada por migration antes deste catálogo ser atualizado), [infoPermissao]
/// cai num fallback legível (módulo = prefixo antes do ponto, rótulo = a
/// própria chave) em vez de quebrar a tela.
library;

class PermissaoInfo {
  const PermissaoInfo(this.modulo, this.label);
  final String modulo;
  final String label;
}

const Map<String, PermissaoInfo> _catalogo = {
  'patrimonio.view': PermissaoInfo('Patrimônios', 'Visualizar patrimônios'),
  'patrimonio.create': PermissaoInfo('Patrimônios', 'Cadastrar patrimônio'),
  'patrimonio.edit': PermissaoInfo('Patrimônios', 'Editar patrimônio'),
  'patrimonio.compare_update': PermissaoInfo('Patrimônios', 'Comparar e atualizar (crítico)'),
  'movimentacao.view': PermissaoInfo('Movimentações', 'Visualizar movimentações'),
  'movimentacao.create': PermissaoInfo('Movimentações', 'Registrar movimentação'),
  'setor.view': PermissaoInfo('Setores', 'Visualizar setores'),
  'setor.manage': PermissaoInfo('Setores', 'Gerenciar setores'),
  'localizacao.view': PermissaoInfo('Localizações', 'Visualizar localizações'),
  'localizacao.manage': PermissaoInfo('Localizações', 'Gerenciar localizações'),
  'tipo_patrimonio.view': PermissaoInfo('Tipos de patrimônio', 'Visualizar tipos de patrimônio'),
  'tipo_patrimonio.manage': PermissaoInfo('Tipos de patrimônio', 'Gerenciar tipos de patrimônio'),
  'sei.view': PermissaoInfo('SEI', 'Visualizar processos SEI'),
  'sei.manage': PermissaoInfo('SEI', 'Gerenciar processos SEI'),
};

/// Ordem de exibição dos módulos — sempre a mesma, independente da ordem em
/// que o servidor devolveu as linhas de `obter_permissoes_usuario`.
const List<String> ordemModulosPermissao = [
  'Patrimônios',
  'Movimentações',
  'Setores',
  'Localizações',
  'Tipos de patrimônio',
  'SEI',
];

PermissaoInfo infoPermissao(String permissionKey) =>
    _catalogo[permissionKey] ?? PermissaoInfo(permissionKey.split('.').first, permissionKey);
