/// Tipos de evento da trilha de auditoria de um documento SEI pendente — a
/// lista cresce conforme novas ações forem implementadas; nunca reescrita
/// retroativamente (eventos são INSERT-only, sem UPDATE/DELETE concedido
/// ao cliente).
enum SeiTipoEventoDocumento {
  criacao,
  edicao,
  decisaoAlterada,
  itemConcluido,
  itemCancelado,
  documentoCancelado,
  tentativaBloqueada;

  static SeiTipoEventoDocumento fromValue(String value) {
    switch (value) {
      case 'CRIACAO':
        return SeiTipoEventoDocumento.criacao;
      case 'EDICAO':
        return SeiTipoEventoDocumento.edicao;
      case 'DECISAO_ALTERADA':
        return SeiTipoEventoDocumento.decisaoAlterada;
      case 'ITEM_CONCLUIDO':
        return SeiTipoEventoDocumento.itemConcluido;
      case 'ITEM_CANCELADO':
        return SeiTipoEventoDocumento.itemCancelado;
      case 'DOCUMENTO_CANCELADO':
        return SeiTipoEventoDocumento.documentoCancelado;
      case 'TENTATIVA_BLOQUEADA':
        return SeiTipoEventoDocumento.tentativaBloqueada;
      default:
        throw ArgumentError('Tipo de evento de documento SEI inválido: $value');
    }
  }

  String get value {
    switch (this) {
      case SeiTipoEventoDocumento.criacao:
        return 'CRIACAO';
      case SeiTipoEventoDocumento.edicao:
        return 'EDICAO';
      case SeiTipoEventoDocumento.decisaoAlterada:
        return 'DECISAO_ALTERADA';
      case SeiTipoEventoDocumento.itemConcluido:
        return 'ITEM_CONCLUIDO';
      case SeiTipoEventoDocumento.itemCancelado:
        return 'ITEM_CANCELADO';
      case SeiTipoEventoDocumento.documentoCancelado:
        return 'DOCUMENTO_CANCELADO';
      case SeiTipoEventoDocumento.tentativaBloqueada:
        return 'TENTATIVA_BLOQUEADA';
    }
  }
}

/// Uma entrada IMUTÁVEL da trilha de auditoria de um documento — nunca
/// editável depois de criada; a UI só lê.
class SeiEventoDocumento {
  factory SeiEventoDocumento.fromJson(Map<String, dynamic> json) {
    final autor = json['autor'] as Map<String, dynamic>?;
    return SeiEventoDocumento(
      id: json['id'] as String,
      documentoId: json['documento_id'] as String,
      itemId: json['item_id'] as String?,
      tipo: SeiTipoEventoDocumento.fromValue(json['tipo'] as String),
      descricao: json['descricao'] as String,
      dadosAntes: json['dados_antes'] as Map<String, dynamic>?,
      dadosDepois: json['dados_depois'] as Map<String, dynamic>?,
      autorId: json['autor_id'] as String,
      autorNome: autor?['nome'] as String? ?? 'Não disponível',
      criadoEm: DateTime.parse(json['criado_em'] as String),
    );
  }

  const SeiEventoDocumento({
    required this.id,
    required this.documentoId,
    this.itemId,
    required this.tipo,
    required this.descricao,
    this.dadosAntes,
    this.dadosDepois,
    required this.autorId,
    required this.autorNome,
    required this.criadoEm,
  });

  final String id;
  final String documentoId;
  final String? itemId;
  final SeiTipoEventoDocumento tipo;
  final String descricao;

  /// Retrato dos campos relevantes antes/depois da ação (ex.: edição de
  /// destino, correção manual) — `null` quando o evento não altera dado
  /// estruturado (ex.: criação).
  final Map<String, Object?>? dadosAntes;
  final Map<String, Object?>? dadosDepois;

  final String autorId;
  final String autorNome;
  final DateTime criadoEm;
}
