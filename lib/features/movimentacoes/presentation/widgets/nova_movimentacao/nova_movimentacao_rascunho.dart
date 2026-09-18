import 'package:flutter/widgets.dart';

import '../../../../patrimonios/domain/patrimonio.dart';
import '../../../domain/movimentacao.dart';
import '../../nova_movimentacao_regras.dart';

/// Como o campo de localização de destino se comporta — só
/// AJUSTE_INVENTARIO tem os três estados (ver `p_localizacao_destino_id` ×
/// `p_limpar_localizacao` em docs/database.md); os demais tipos só usam
/// [manter] (nada escolhido = não informar) ou [definir].
enum LocalizacaoEscolha {
  /// `p_localizacao_destino_id = null`, `p_limpar_localizacao = false` —
  /// preserva a localização atual (só tem efeito real em AJUSTE_INVENTARIO;
  /// nos demais tipos o setor muda, então não há "atual" a preservar).
  manter,

  /// `p_localizacao_destino_id = <escolhida>`.
  definir,

  /// `p_limpar_localizacao = true` — só aceito pela RPC quando o tipo é
  /// AJUSTE_INVENTARIO.
  limpar,
}

/// Estado mutável do wizard de Nova Movimentação (PROMPT 10.2), compartilhado
/// entre os passos do formulário. Um objeto mutável (em vez do padrão
/// imutável + copyWith usado nos filtros de listagem) porque vários widgets
/// de passo diferentes editam pedaços dele — o dono (`NovaMovimentacaoDialog`)
/// chama `setState` depois de cada mudança; os `TextEditingController` são
/// dele mesmo, então o texto nunca é perdido ao trocar de passo.
class NovaMovimentacaoRascunho {
  MovimentacaoTipo? tipo;
  String? destinoSetorId;
  LocalizacaoEscolha localizacaoEscolha = LocalizacaoEscolha.manter;
  String? localizacaoDestinoId;
  final responsavelController = TextEditingController();
  final motivoController = TextEditingController();
  final observacaoController = TextEditingController();
  final documentoController = TextEditingController();
  final chamadoController = TextEditingController();

  /// Só usado quando [tipo] é BAIXA — reforço de confirmação (seção 9 do
  /// prompt), nunca enviado à RPC.
  bool confirmacaoBaixa = false;

  void dispose() {
    responsavelController.dispose();
    motivoController.dispose();
    observacaoController.dispose();
    documentoController.dispose();
    chamadoController.dispose();
  }
}

/// Gate do botão "Avançar" do passo Detalhes (PROMPT 10.2, seção 15: nunca
/// tratar `null`/vazio/`false` como equivalentes) — só verificação de UX; a
/// RPC valida tudo de novo e é a autoridade final mesmo se algo escapar
/// daqui.
bool detalhesValidos(NovaMovimentacaoRascunho r, Patrimonio patrimonio) {
  final tipo = r.tipo;
  if (tipo == null) return false;

  if (tipoExigeDestino(tipo) && r.destinoSetorId == null) return false;

  // RPC real (PROMPT 10.2.2, seção 3): "Destino igual ao setor atual do
  // patrimônio não é permitido para %" — para estes seis tipos a UI já
  // filtra o setor atual do seletor (ver `_SetorDestinoField`), mas esta
  // checagem é a garantia real, igual ao double-submit: nunca confia só na
  // opção não ter sido oferecida.
  if (tipoExigeDestinoDiferente(tipo) && r.destinoSetorId == patrimonio.setorAtualId) {
    return false;
  }

  final interna = ehTransferenciaInterna(
    tipo: tipo,
    destinoId: r.destinoSetorId,
    setorAtualId: patrimonio.setorAtualId,
  );
  if (interna) {
    if (r.localizacaoEscolha != LocalizacaoEscolha.definir || r.localizacaoDestinoId == null) {
      return false;
    }
    // RPC real: "A localização de destino precisa ser diferente da
    // localização atual" — movimentação interna sem trocar a localização
    // não faz nada.
    if (r.localizacaoDestinoId == patrimonio.localizacaoAtualId) return false;
  }

  // AJUSTE_INVENTARIO em patrimônio BAIXADO (PROMPT 10.2.2, seção 6): a RPC
  // proíbe mudar setor/localização mesmo que o campo tenha sido montado
  // antes do status virar BAIXADO (ex.: concorrência) — a UI já esconde
  // esses campos nesse caso, mas o gate abaixo garante que um rascunho
  // "herdado" de outro status nunca passa disfarçado.
  if (tipo == MovimentacaoTipo.ajusteInventario && patrimonio.status == PatrimonioStatus.baixado) {
    if (r.destinoSetorId != null && r.destinoSetorId != patrimonio.setorAtualId) return false;
    if (r.localizacaoEscolha != LocalizacaoEscolha.manter) return false;
  }

  // AJUSTE_INVENTARIO com "Definir nova localização" escolhido mas nenhuma
  // localização selecionada ainda — nunca deixa passar um id nulo
  // disfarçado de escolha válida.
  if (tipoPermiteLimparLocalizacao(tipo) &&
      r.localizacaoEscolha == LocalizacaoEscolha.definir &&
      r.localizacaoDestinoId == null) {
    return false;
  }

  if (tipoExigeResponsavel(tipo) && r.responsavelController.text.trim().isEmpty) {
    return false;
  }

  if (tipo == MovimentacaoTipo.alteracaoResponsavel) {
    final novo = r.responsavelController.text.trim();
    final atual = patrimonio.responsavelAtual?.trim();
    if (novo.isNotEmpty && atual != null && novo.toLowerCase() == atual.toLowerCase()) {
      return false;
    }
  }

  return true;
}
