/// Texto de exibição compacta de um setor — a sigla real cadastrada no
/// InvTec (coluna `setores.sigla`), nunca uma abreviação
/// inventada a partir das iniciais do nome. Sem sigla cadastrada, cai para
/// o nome completo disponível; sem nenhum dos dois, `null` (o chamador
/// decide o fallback visual, ex.: `?? '—'`, igual ao resto do app).
///
/// Usado em todo contexto compacto (tabelas, dropdowns, detalhamentos) —
/// nunca substitui o nome completo em contextos com espaço de sobra
/// (diálogos amplos, tooltips): ali o nome completo continua sendo o mais
/// claro.
String? siglaOuNomeSetor({String? sigla, String? nome}) {
  final siglaAparada = sigla?.trim();
  if (siglaAparada != null && siglaAparada.isNotEmpty) return siglaAparada;

  final nomeAparado = nome?.trim();
  return (nomeAparado == null || nomeAparado.isEmpty) ? null : nomeAparado;
}
