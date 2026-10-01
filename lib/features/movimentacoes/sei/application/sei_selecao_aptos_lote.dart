import '../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../domain/sei_documento_pendente.dart';
import '../domain/sei_item_pendente.dart';
import 'sei_conclusao_lote_plano.dart';
import 'sei_pendencia_regras.dart';

/// Um item PENDENTE que "Concluir todos os aptos" NÃO incluiu na seleção —
/// sempre acompanhado do(s) motivo(s), NUNCA some silenciosamente da tela
/// (PROMPT 11.5.6).
class SeiItemNaoIncluidoLote {
  const SeiItemNaoIncluidoLote({required this.item, required this.motivos});

  final SeiItemPendente item;
  final List<String> motivos;
}

/// Resultado de "Concluir todos os aptos" (PROMPT 11.5.6) — PURO, sem I/O.
/// Separa a seleção em duas listas DISTINTAS: só [aptos] pode virar
/// `itemIds` de uma chamada a `concluirItensLote`; [naoIncluidos] é
/// exclusivamente informativo (nunca enviado à RPC).
class SeiSelecaoAptosLote {
  const SeiSelecaoAptosLote({required this.aptos, required this.naoIncluidos, required this.excedeLimite});

  /// Itens PENDENTES com todas as pré-condições técnicas já resolvidas
  /// (mesma regra de [itemElegivelParaConclusaoFutura]) — a seleção que a
  /// ação proporia, ANTES de qualquer confirmação do usuário.
  final List<SeiItemPendente> aptos;

  /// Todo item de [SeiSelecaoAptosLote] que ficou de fora de [aptos], com o
  /// motivo — inclui itens já CONCLUÍDOS/CANCELADOS (o motivo deixa isso
  /// explícito) e itens PENDENTES mas tecnicamente bloqueados.
  final List<SeiItemNaoIncluidoLote> naoIncluidos;

  /// `true` quando [aptos] sozinho já ultrapassa [limiteItensLote] — esta
  /// função NUNCA trunca a lista automaticamente: cabe a uma decisão
  /// EXPLÍCITA do usuário (a futura tela mostra um bloqueio, não corta a
  /// seleção sozinha).
  final bool excedeLimite;

  int get totalAptos => aptos.length;
}

/// Separa [itens] (todos os itens de UM documento, de qualquer status) em
/// aptos/não incluídos para a ação "Concluir todos os aptos" — reaproveita
/// [itensElegiveisParaConclusaoFutura] sem alteração para decidir quem
/// entra, e [motivosNaoElegivelParaConclusaoFutura] para explicar quem
/// fica de fora.
SeiSelecaoAptosLote selecionarAptosParaLote(List<SeiItemPendente> itens) {
  final aptos = itensElegiveisParaConclusaoFutura(itens);
  final aptosIds = aptos.map((i) => i.id).toSet();
  final naoIncluidos = [
    for (final item in itens)
      if (!aptosIds.contains(item.id))
        SeiItemNaoIncluidoLote(item: item, motivos: motivosNaoElegivelParaConclusaoFutura(item)),
  ];
  return SeiSelecaoAptosLote(aptos: aptos, naoIncluidos: naoIncluidos, excedeLimite: aptos.length > limiteItensLote);
}

/// PROMPT 11.5.10/11.5.10.1 — refina [selecionarAptosParaLote] (a triagem
/// PRELIMINAR, só por item) contra a situação ATUAL de cada patrimônio —
/// PURA, sem I/O: [patrimoniosPorItemId] já vem pronto (buscar os
/// patrimônios é responsabilidade de quem chama, ex.:
/// `_SeiPendenciaDetalheDialogState._buscarPatrimoniosAtuais`). Reaproveita
/// [planejarConclusaoLote] (nenhuma regra de elegibilidade nova/duplicada
/// — a mesma função que a revisão final usa) para decidir, ITEM A ITEM
/// dentre os candidatos preliminares, quem de fato permanece apto; quem
/// não permanece entra em [SeiSelecaoAptosLote.naoIncluidos] com o motivo
/// REAL (ex.: "Origem divergente: ..."), ao lado dos já excluídos pela
/// triagem preliminar (decisão pendente, status terminal etc.).
///
/// PROMPT 11.5.10.1 — [SeiSelecaoAptosLote.excedeLimite] é calculado sobre
/// a contagem FINAL (depois desta reavaliação), nunca sobre a triagem
/// preliminar: um documento com, por exemplo, 201 candidatos preliminares
/// dos quais 2 são bloqueados aqui (199 efetivos) precisa ser PERMITIDO —
/// rejeitar com base na contagem preliminar seria um falso positivo que a
/// própria consulta já desmentiu. O inverso (a reavaliação AUMENTAR a
/// contagem) nunca acontece: ela só pode remover itens dos aptos
/// preliminares, nunca adicionar um que a triagem já tinha descartado.
SeiSelecaoAptosLote selecionarAptosParaLoteComPatrimonios({
  required SeiDocumentoPendente documento,
  required Map<String, PatrimonioDetalhe?> patrimoniosPorItemId,
}) {
  final preliminar = selecionarAptosParaLote(documento.itens);
  if (preliminar.aptos.isEmpty) return preliminar;

  final plano = planejarConclusaoLote(
    documento: documento,
    itensSelecionados: preliminar.aptos,
    patrimoniosPorItemId: patrimoniosPorItemId,
  );

  final aptos = <SeiItemPendente>[];
  final naoIncluidos = [...preliminar.naoIncluidos];
  for (final itemPlano in plano.itens) {
    if (itemPlano.plano.podeConfirmar) {
      aptos.add(itemPlano.item);
    } else {
      naoIncluidos.add(SeiItemNaoIncluidoLote(item: itemPlano.item, motivos: itemPlano.plano.bloqueios));
    }
  }

  return SeiSelecaoAptosLote(aptos: aptos, naoIncluidos: naoIncluidos, excedeLimite: aptos.length > limiteItensLote);
}
