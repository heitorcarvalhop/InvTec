/// Decisão humana explícita para um campo de destino que o documento SEI
/// nunca informa — localização e responsável.
///
/// A RPC real de TRANSFERENCIA grava `p_localizacao_destino_id`/
/// `p_responsavel_destino` EXATAMENTE como enviados: omitir (`null`) não
/// preserva o valor atual, ele APAGA. Como o PDF nunca traz esses dois
/// campos, "ausência de informação no documento" NUNCA pode ser tratada
/// como "autorização automática para limpar" — por isso todo item começa
/// [pendente] e só sai desse estado por uma ação explícita do usuário,
/// nunca por inferência do parser/analyzer.
enum SeiDecisaoCampo {
  /// Nenhuma decisão tomada ainda — bloqueia a elegibilidade do item no
  /// plano de execução.
  pendente,

  /// O usuário escolheu um valor explícito (uma localização real do setor
  /// de destino, ou um texto de responsável).
  definido,

  /// O usuário confirmou EXPLICITAMENTE que o campo deve ficar sem
  /// informação — distinto de [pendente]: aqui já houve uma decisão
  /// consciente, só que o valor escolhido é "nenhum".
  confirmadoSemInformacao;

  static SeiDecisaoCampo fromValue(String value) {
    switch (value) {
      case 'PENDENTE':
        return SeiDecisaoCampo.pendente;
      case 'DEFINIDO':
        return SeiDecisaoCampo.definido;
      case 'CONFIRMADO_SEM_INFORMACAO':
        return SeiDecisaoCampo.confirmadoSemInformacao;
      default:
        throw ArgumentError('Decisão de campo SEI inválida: $value');
    }
  }

  String get value {
    switch (this) {
      case SeiDecisaoCampo.pendente:
        return 'PENDENTE';
      case SeiDecisaoCampo.definido:
        return 'DEFINIDO';
      case SeiDecisaoCampo.confirmadoSemInformacao:
        return 'CONFIRMADO_SEM_INFORMACAO';
    }
  }
}
