/// Status individual de um item de uma solicitação pendente (PROMPT 11.3,
/// seção 6) — SEMPRE persistido, nunca inferido só pela UI.
///
/// [concluido] só pode significar "existe movimentação efetiva
/// correspondente registrada com sucesso" (seção 6): nenhuma checkbox ou
/// confirmação visual, isolada, pode atribuir este status — a
/// transição para [concluido] exige, na base, um `movimentacao_id`
/// preenchido (ver constraint `documentos_sei_itens_status_coerente` na
/// migration). Nenhuma etapa desta versão do app executa essa transição.
enum SeiItemPendenciaStatus {
  pendente,
  concluido,
  cancelado;

  static SeiItemPendenciaStatus fromValue(String value) {
    switch (value) {
      case 'PENDENTE':
        return SeiItemPendenciaStatus.pendente;
      case 'CONCLUIDO':
        return SeiItemPendenciaStatus.concluido;
      case 'CANCELADO':
        return SeiItemPendenciaStatus.cancelado;
      default:
        throw ArgumentError('Status de item de pendência SEI inválido: $value');
    }
  }

  String get value {
    switch (this) {
      case SeiItemPendenciaStatus.pendente:
        return 'PENDENTE';
      case SeiItemPendenciaStatus.concluido:
        return 'CONCLUIDO';
      case SeiItemPendenciaStatus.cancelado:
        return 'CANCELADO';
    }
  }
}

extension SeiItemPendenciaStatusLabel on SeiItemPendenciaStatus {
  String get label {
    switch (this) {
      case SeiItemPendenciaStatus.pendente:
        return 'Pendente';
      case SeiItemPendenciaStatus.concluido:
        return 'Concluído';
      case SeiItemPendenciaStatus.cancelado:
        return 'Cancelado';
    }
  }
}
