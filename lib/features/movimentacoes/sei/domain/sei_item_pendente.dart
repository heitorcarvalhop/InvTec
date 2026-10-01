import 'sei_decisao_campo.dart';
import 'sei_item_pendencia_status.dart';
import 'sei_valor_corrigivel.dart';

/// O que uma linha da análise do PDF vira ao ser salva como pendência —
/// construído pela camada `application`
/// (`construirDocumentoPendenteRascunho`), nunca montado à mão pela UI.
/// Ainda sem id: é o que o repositório envia para persistir.
class SeiItemPendenteRascunho {
  const SeiItemPendenteRascunho({
    required this.linha,
    this.patrimonioId,
    required this.numeroPatrimonioOriginal,
    required this.origemTextoOriginal,
    this.origemSetorId,
    required this.destinoTextoOriginal,
    this.destinoSetorId,
    required this.numeroChamadoOriginal,
    required this.equipamentoTextoOriginal,
    this.localizacaoDestinoId,
    this.localizacaoDestinoNome,
    this.decisaoLocalizacao = SeiDecisaoCampo.pendente,
    this.responsavelDestino,
    this.decisaoResponsavel = SeiDecisaoCampo.pendente,
  });

  final int linha;

  /// `null` quando o número do patrimônio do documento não foi encontrado
  /// no InvTec — a linha ainda assim vira um item da pendência (a
  /// pendência é o registro da SOLICITAÇÃO, que existe mesmo que um item
  /// precise de correção manual antes de poder ser concluído).
  final String? patrimonioId;

  final String? numeroPatrimonioOriginal;
  final String? origemTextoOriginal;
  final String? origemSetorId;
  final String? destinoTextoOriginal;
  final String? destinoSetorId;
  final String? numeroChamadoOriginal;
  final String? equipamentoTextoOriginal;

  final String? localizacaoDestinoId;
  final String? localizacaoDestinoNome;
  final SeiDecisaoCampo decisaoLocalizacao;

  final String? responsavelDestino;
  final SeiDecisaoCampo decisaoResponsavel;
}

/// Item PERSISTIDO de um documento SEI pendente — nunca alimenta
/// `registrarMovimentacao` diretamente; [movimentacaoId] só é preenchido
/// quando o item é concluído via `concluir_item_documento_sei`.
class SeiItemPendente {
  factory SeiItemPendente.fromJson(Map<String, dynamic> json) {
    final patrimonio = json['patrimonio'] as Map<String, dynamic>?;
    final origemSetor = json['origem_setor'] as Map<String, dynamic>?;
    final destinoSetor = json['destino_setor'] as Map<String, dynamic>?;
    final localizacaoDestino = json['localizacao_destino'] as Map<String, dynamic>?;
    final corretor = json['corretor'] as Map<String, dynamic>?;
    final corrigidoPorId = json['corrigido_por'] as String?;
    final corrigidoEmTexto = json['corrigido_em'] as String?;
    final motivoCorrecao = json['motivo_correcao'] as String?;

    SeiValorCorrigivel<String> corrigivel(String chaveOriginal, String? chaveCorrigido) {
      final corrigido = chaveCorrigido == null ? null : json[chaveCorrigido] as String?;
      return SeiValorCorrigivel<String>(
        original: json[chaveOriginal] as String?,
        corrigido: corrigido,
        corrigidoPorId: corrigido == null ? null : corrigidoPorId,
        corrigidoPorNome: corrigido == null ? null : corretor?['nome'] as String?,
        corrigidoEm: corrigido == null || corrigidoEmTexto == null ? null : DateTime.parse(corrigidoEmTexto),
        motivoCorrecao: corrigido == null ? null : motivoCorrecao,
      );
    }

    return SeiItemPendente(
      id: json['id'] as String,
      documentoId: json['documento_id'] as String,
      linha: json['linha'] as int,
      patrimonioId: json['patrimonio_id'] as String?,
      numeroPatrimonio: corrigivel('numero_patrimonio_original', 'numero_patrimonio_corrigido'),
      origemTexto: corrigivel('origem_texto_original', null),
      origemSetorId: json['origem_setor_id'] as String?,
      destinoTexto: corrigivel('destino_texto_original', 'destino_texto_corrigido'),
      destinoSetorId: json['destino_setor_id'] as String?,
      numeroChamado: corrigivel('numero_chamado_original', 'numero_chamado_corrigido'),
      equipamentoTexto: corrigivel('equipamento_texto_original', 'equipamento_texto_corrigido'),
      localizacaoDestinoId: json['localizacao_destino_id'] as String?,
      localizacaoDestinoNome: localizacaoDestino?['nome'] as String?,
      decisaoLocalizacao: SeiDecisaoCampo.fromValue(json['decisao_localizacao'] as String),
      responsavelDestino: json['responsavel_destino'] as String?,
      decisaoResponsavel: SeiDecisaoCampo.fromValue(json['decisao_responsavel'] as String),
      status: SeiItemPendenciaStatus.fromValue(json['status'] as String),
      motivoCancelamento: json['motivo_cancelamento'] as String?,
      movimentacaoId: json['movimentacao_id'] as String?,
      criadoEm: DateTime.parse(json['criado_em'] as String),
      atualizadoEm: json['atualizado_em'] == null ? null : DateTime.parse(json['atualizado_em'] as String),
      patrimonioNumero: patrimonio?['numero_patrimonio'] as String?,
      origemSetorNome: origemSetor?['nome'] as String?,
      destinoSetorNome: destinoSetor?['nome'] as String?,
      origemSetorSigla: origemSetor?['sigla'] as String?,
      destinoSetorSigla: destinoSetor?['sigla'] as String?,
    );
  }

  const SeiItemPendente({
    required this.id,
    required this.documentoId,
    required this.linha,
    this.patrimonioId,
    required this.numeroPatrimonio,
    required this.origemTexto,
    this.origemSetorId,
    required this.destinoTexto,
    this.destinoSetorId,
    required this.numeroChamado,
    required this.equipamentoTexto,
    this.localizacaoDestinoId,
    this.localizacaoDestinoNome,
    this.decisaoLocalizacao = SeiDecisaoCampo.pendente,
    this.responsavelDestino,
    this.decisaoResponsavel = SeiDecisaoCampo.pendente,
    required this.status,
    this.motivoCancelamento,
    this.movimentacaoId,
    required this.criadoEm,
    this.atualizadoEm,
    this.patrimonioNumero,
    this.origemSetorNome,
    this.destinoSetorNome,
    this.origemSetorSigla,
    this.destinoSetorSigla,
  });

  final String id;
  final String documentoId;
  final int linha;

  final String? patrimonioId;

  /// Só para exibição (resolvido via embed) — a identidade real é
  /// [patrimonioId]; nunca usado para decisão de negócio.
  final String? patrimonioNumero;

  final SeiValorCorrigivel<String> numeroPatrimonio;
  final SeiValorCorrigivel<String> origemTexto;
  final String? origemSetorId;
  final String? origemSetorNome;
  final String? origemSetorSigla;
  final SeiValorCorrigivel<String> destinoTexto;
  final String? destinoSetorId;
  final String? destinoSetorNome;
  final String? destinoSetorSigla;
  final SeiValorCorrigivel<String> numeroChamado;
  final SeiValorCorrigivel<String> equipamentoTexto;

  final String? localizacaoDestinoId;
  final String? localizacaoDestinoNome;
  final SeiDecisaoCampo decisaoLocalizacao;

  final String? responsavelDestino;
  final SeiDecisaoCampo decisaoResponsavel;

  final SeiItemPendenciaStatus status;

  /// Obrigatório (na base, por CHECK) quando [status] é
  /// [SeiItemPendenciaStatus.cancelado].
  final String? motivoCancelamento;

  /// Obrigatório (na base, por CHECK) quando [status] é
  /// [SeiItemPendenciaStatus.concluido] — o vínculo inequívoco com a
  /// movimentação efetiva.
  final String? movimentacaoId;

  final DateTime criadoEm;
  final DateTime? atualizadoEm;

  SeiItemPendente copyWith({
    SeiValorCorrigivel<String>? numeroPatrimonio,
    SeiValorCorrigivel<String>? origemTexto,
    SeiValorCorrigivel<String>? destinoTexto,
    String? Function()? destinoSetorId,
    String? Function()? destinoSetorNome,
    SeiValorCorrigivel<String>? numeroChamado,
    SeiValorCorrigivel<String>? equipamentoTexto,
    String? Function()? localizacaoDestinoId,
    String? Function()? localizacaoDestinoNome,
    SeiDecisaoCampo? decisaoLocalizacao,
    String? Function()? responsavelDestino,
    SeiDecisaoCampo? decisaoResponsavel,
    SeiItemPendenciaStatus? status,
    String? Function()? motivoCancelamento,
    String? Function()? movimentacaoId,
    DateTime? atualizadoEm,
  }) {
    return SeiItemPendente(
      id: id,
      documentoId: documentoId,
      linha: linha,
      patrimonioId: patrimonioId,
      numeroPatrimonio: numeroPatrimonio ?? this.numeroPatrimonio,
      origemTexto: origemTexto ?? this.origemTexto,
      origemSetorId: origemSetorId,
      destinoTexto: destinoTexto ?? this.destinoTexto,
      destinoSetorId: destinoSetorId != null ? destinoSetorId() : this.destinoSetorId,
      numeroChamado: numeroChamado ?? this.numeroChamado,
      equipamentoTexto: equipamentoTexto ?? this.equipamentoTexto,
      localizacaoDestinoId: localizacaoDestinoId != null ? localizacaoDestinoId() : this.localizacaoDestinoId,
      localizacaoDestinoNome: localizacaoDestinoNome != null ? localizacaoDestinoNome() : this.localizacaoDestinoNome,
      decisaoLocalizacao: decisaoLocalizacao ?? this.decisaoLocalizacao,
      responsavelDestino: responsavelDestino != null ? responsavelDestino() : this.responsavelDestino,
      decisaoResponsavel: decisaoResponsavel ?? this.decisaoResponsavel,
      status: status ?? this.status,
      motivoCancelamento: motivoCancelamento != null ? motivoCancelamento() : this.motivoCancelamento,
      movimentacaoId: movimentacaoId != null ? movimentacaoId() : this.movimentacaoId,
      criadoEm: criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      patrimonioNumero: patrimonioNumero,
      origemSetorNome: origemSetorNome,
      destinoSetorNome: destinoSetorNome != null ? destinoSetorNome() : this.destinoSetorNome,
      origemSetorSigla: origemSetorSigla,
      destinoSetorSigla: destinoSetorSigla,
    );
  }
}
