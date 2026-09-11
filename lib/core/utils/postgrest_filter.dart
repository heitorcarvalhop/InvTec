/// Encapsula um valor de busca do usuário para uso seguro dentro de uma
/// string de filtro montada manualmente para `.or(...)` do Postgrest (ex.:
/// `'nome.ilike.${postgrestFilterValue('%$termo%')}'`).
///
/// O Postgrest usa `,` para separar condições e `(`/`)` para agrupamento
/// dentro de `or=`; um termo de busca livre pode conter esses caracteres e
/// quebrar (ou adulterar) o filtro se for interpolado cru. A sintaxe do
/// Postgrest permite escapar isso citando o valor entre aspas duplas, com
/// `"` e `\` escapados por `\`. Sempre citamos, independentemente do
/// conteúdo — mais simples e seguro do que tentar detectar quais
/// caracteres precisam de escape.
String postgrestFilterValue(String valor) {
  final escapado = valor.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  return '"$escapado"';
}
