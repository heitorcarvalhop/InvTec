/// Estágios explícitos da preparação de uma execução futura (PROMPT 11.2,
/// seção 2) — nenhum deles, isolado ou combinado, e nenhuma tela desta
/// versão, autoriza uma escrita real: o controller continua incapaz de
/// chamar `registrarMovimentacao` (só passou também a LER
/// `MovimentacaoRepository.listar`, para checagem de duplicidade — seção
/// 4).
///
/// O status PRONTO/AVISO/BLOQUEADO de `SeiValidacaoItem` é só validação
/// TÉCNICA (o parser conseguiu ler o número, ele existe no InvTec, a
/// transição é permitida pela RPC). Isso nunca significa que o despacho foi
/// de fato cumprido nem que existe autorização administrativa para alterar
/// o estado patrimonial — daí esta distinção.
enum SeiEstagioPreparacao {
  /// O parser leu o PDF e extraiu metadados + itens — ainda sem nenhum
  /// cruzamento com o InvTec.
  documentoInterpretado,

  /// Cruzamento READ-ONLY concluído: cada item tem um status
  /// PRONTO/AVISO/BLOQUEADO (`SeiAnaliseResultado` calculado).
  patrimoniosConferidos,

  /// Pré-condições técnicas para uma futura execução em lote já foram
  /// checadas: duplicidade verificada, avisos de confiança média
  /// confirmados linha a linha, nenhuma linha selecionada está
  /// desatualizada. Ainda NÃO é autorização — só elegibilidade técnica.
  aptoParaExecucao,

  /// O usuário confirmou explicitamente, através do aviso da seção 2, que o
  /// procedimento patrimonial foi de fato autorizado e que deseja que as
  /// movimentações sejam registradas. Mesmo neste estágio, esta versão não
  /// disponibiliza nenhum botão que chame `registrarMovimentacao`.
  autorizado,
}
