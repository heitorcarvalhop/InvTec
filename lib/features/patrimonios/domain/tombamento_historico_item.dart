/// Uma linha de `patrimonio_tombamentos_historico` (migration 3A.4),
/// exibida na tela de detalhe do patrimônio. Imutável — o histórico nunca
/// é editado/apagado por usuários comuns (mesma garantia de
/// [docs/database.md], seção "Histórico imutável", já aplicada ao
/// histórico de movimentações).
///
/// [numeroAnterior]/[numeroNovo] são os valores BRUTOS como estavam/
/// ficaram em `patrimonios.numero_patrimonio` — nunca normalizados (zeros
/// à esquerda preservados exatamente como armazenados).
///
/// [registradoEm] é quando este evento foi GRAVADO no InvTec — não
/// confundir com "quando a troca física aconteceu". Só [dataEfetivaAlteracao]
/// (presente apenas quando [origem] é `'MANUAL'`) responde a essa segunda
/// pergunta; para os demais, a data real da troca nunca é conhecida com
/// certeza, então nunca é inventada.
class TombamentoHistoricoItem {
  const TombamentoHistoricoItem({
    required this.sequencia,
    required this.numeroAnterior,
    required this.numeroNovo,
    required this.origem,
    required this.registradoEm,
    this.dataEfetivaAlteracao,
    this.observacao,
  });

  factory TombamentoHistoricoItem.fromJson(Map<String, dynamic> json) {
    return TombamentoHistoricoItem(
      sequencia: json['sequencia'] as int,
      numeroAnterior: json['numero_anterior'] as String?,
      numeroNovo: json['numero_novo'] as String?,
      origem: json['origem'] as String,
      registradoEm: DateTime.parse(json['registrado_em'] as String),
      dataEfetivaAlteracao: json['data_efetiva_alteracao'] == null
          ? null
          : DateTime.parse(json['data_efetiva_alteracao'] as String),
      observacao: json['observacao'] as String?,
    );
  }

  /// Ordem real de inserção (nunca recalculável a partir de [registradoEm],
  /// que pode empatar entre eventos da mesma transação) — usada só para
  /// ordenar a lista, nunca exibida diretamente.
  final int sequencia;
  final String? numeroAnterior;
  final String? numeroNovo;

  /// `'MANUAL' | 'ALTERACAO_DIRETA' | 'ADMINISTRATIVA' | 'IMPORTACAO_PLANILHA'`.
  final String origem;
  final DateTime registradoEm;
  final DateTime? dataEfetivaAlteracao;
  final String? observacao;
}

/// Rótulo em português para [TombamentoHistoricoItem.origem] — vocabulário
/// fechado (mesmo CHECK da migration 3A.4); qualquer valor fora dele é um
/// bug de schema, nunca um dado real possível.
String origemTombamentoHistoricoLabel(String origem) {
  switch (origem) {
    case 'MANUAL':
      return 'Alteração manual';
    case 'ALTERACAO_DIRETA':
      return 'Alteração direta';
    case 'ADMINISTRATIVA':
      return 'Alteração administrativa';
    case 'IMPORTACAO_PLANILHA':
      return 'Planilha oficial';
    default:
      return origem;
  }
}
