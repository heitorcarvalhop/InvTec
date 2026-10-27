/// Uma linha JÁ decodificada de `InvTec_plano_reclassificacao_104.csv`
/// (arquivo local, fora do Git) — nenhum campo aqui é resolvido contra o
/// InvTec ainda (isso é responsabilidade de `RetificacaoComparador`); esta
/// classe só representa o TEXTO BRUTO de cada coluna, já separado.
///
/// Layout confirmado do CSV (separador `;`, 17 colunas, cabeçalho na linha
/// 1): ID patrimônio no InvTec; Tombamento oficial (texto); Tombamento
/// atual no InvTec; Descrição oficial; Setor atual (InvTec); Unidade
/// correta (sigla); Unidade correta (nome); Localização atual no InvTec;
/// Localização na planilha; Localização planejada; Série InvTec; Série
/// oficial; Tombamento anterior planilha; Status tombamento anterior;
/// Status cruzamento; Status da revisão; Observação / justificativa.
class RetificacaoCsvLinha {
  const RetificacaoCsvLinha({
    required this.numeroLinha,
    required this.patrimonioId,
    required this.tombamentoOficial,
    required this.tombamentoAtualInvtec,
    required this.descricaoOficial,
    required this.setorAtualTexto,
    required this.unidadeCorretaSigla,
    required this.unidadeCorretaNome,
    this.localizacaoAtualTexto,
    this.localizacaoPlanilhaTexto,
    this.localizacaoPlanejadaTexto,
    this.serieInvtec,
    this.serieOficial,
    this.tombamentoAnteriorPlanilha,
    this.statusTombamentoAnterior,
    this.statusCruzamento,
    this.statusRevisao,
    this.observacao,
  });

  /// Linha no arquivo original (1-based, cabeçalho = linha 1) — para o
  /// usuário localizar a linha no CSV ao investigar um bloqueio.
  final int numeroLinha;

  final String patrimonioId;
  final String tombamentoOficial;
  final String tombamentoAtualInvtec;
  final String descricaoOficial;
  final String setorAtualTexto;
  final String unidadeCorretaSigla;
  final String unidadeCorretaNome;

  /// Localização que a planilha afirma estar cadastrada HOJE no InvTec —
  /// só para conferência visual na prévia, nunca resolvida/aplicada
  /// automaticamente (ver `RetificacaoComparador`).
  final String? localizacaoAtualTexto;

  /// Texto livre da planilha descrevendo a localização física — igual a
  /// [localizacaoPlanejadaTexto] na maioria das linhas observadas, mas
  /// tratado como coluna independente (a planilha pode diferenciar os dois
  /// em revisões futuras).
  final String? localizacaoPlanilhaTexto;

  /// Localização pretendida na unidade de DESTINO — NUNCA resolvida contra
  /// um catálogo nem criada automaticamente: a unidade de destino
  /// tipicamente não tem esta localização cadastrada ainda (é uma unidade
  /// nova para o patrimônio). Puramente informativa na prévia; a
  /// retificação em si sempre limpa a localização atual (ver
  /// `RetificacaoItem`/migration `retificar_unidade_patrimonio`).
  final String? localizacaoPlanejadaTexto;

  final String? serieInvtec;
  final String? serieOficial;
  final String? tombamentoAnteriorPlanilha;
  final String? statusTombamentoAnterior;
  final String? statusCruzamento;
  final String? statusRevisao;
  final String? observacao;
}
