/// Direção de ordenação — compartilhada por qualquer listagem do InvTec que
/// ofereça ordenação (Patrimônios, Movimentações, e outras no futuro), para
/// nunca duplicar o mesmo conceito com nomes diferentes por tela.
enum OrdenacaoDirecao { asc, desc }

/// Ciclo padrão de clique num cabeçalho/controle de ordenação, igual em
/// qualquer tela do InvTec que tenha colunas ordenáveis:
///
/// 1. campo diferente do atual -> passa a ordenar por ele, ASC;
/// 2. mesmo campo, hoje ASC -> DESC;
/// 3. mesmo campo, hoje DESC -> volta à ordenação padrão da tela (campo
///    `null`, direção `null`).
///
/// [T] é o enum de campo ordenável de cada tela (ex.:
/// `PatrimonioOrdenacaoCampo`) — esta função não conhece esses enums, só o
/// ciclo em si, para a mesma lógica nunca ser reescrita por tela.
(T? campo, OrdenacaoDirecao? direcao) proximoEstadoDeOrdenacao<T>({
  required T? campoAtual,
  required OrdenacaoDirecao? direcaoAtual,
  required T campoClicado,
}) {
  if (campoAtual != campoClicado) return (campoClicado, OrdenacaoDirecao.asc);
  if (direcaoAtual == OrdenacaoDirecao.asc) return (campoClicado, OrdenacaoDirecao.desc);
  return (null, null);
}
