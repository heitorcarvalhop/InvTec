/// decisão do ADMIN sobre UM campo divergente de UM
/// patrimônio, no modo "Comparar e Atualizar". Puramente em memória nesta
/// etapa: nenhuma persistência, nenhuma chamada de rede — só o
/// que a tela de revisão precisa para lembrar o que foi decidido enquanto
/// o usuário navega entre filtros/pesquisa/resumo.
enum DecisaoCampoValor {
  /// Nenhuma decisão tomada ainda — nem aplicar, nem ignorar.
  pendente,

  /// Aplicar o valor da PLANILHA a este campo — nunca executado nesta
  /// etapa, só marcado para a futura etapa de execução.
  aplicar,

  /// Manter o valor ATUAL do InvTec, ignorando a divergência encontrada
  /// neste campo.
  ignorar,
}

/// Identifica de forma ESTÁVEL uma decisão — [patrimonioId] (nunca o
/// número da linha nem uma posição na lista, que mudam com filtros/
/// ordenação) e o rótulo do campo (mesmo texto de [CampoDivergente.campo], ex.:
/// "Descrição", "Localização atual" — único por patrimônio, já que
/// [PatrimonioComparador] nunca gera duas divergências do mesmo campo para
/// o mesmo patrimônio). Usada como chave de um `Map`, por isso `==`/
/// `hashCode` são de VALOR, nunca de identidade do objeto.
class ChaveDecisaoCampo {
  const ChaveDecisaoCampo({required this.patrimonioId, required this.campo});

  final String patrimonioId;
  final String campo;

  @override
  bool operator ==(Object other) =>
      other is ChaveDecisaoCampo && other.patrimonioId == patrimonioId && other.campo == campo;

  @override
  int get hashCode => Object.hash(patrimonioId, campo);

  @override
  String toString() => 'ChaveDecisaoCampo($patrimonioId, $campo)';
}
