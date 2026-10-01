import 'sei_decisao_campo.dart';
import 'sei_duplicidade.dart';

/// Estado de PREPARAÇÃO de uma linha, mantido pela UI/controller —
/// deliberadamente separado de `SeiValidacaoItem` (que é puro, recalculado
/// a cada análise/revalidação): seleção e confirmação são decisões do
/// usuário, nunca resultado de parsing.
class SeiItemExecucaoEstado {
  const SeiItemExecucaoEstado({
    this.selecionado = false,
    this.avisoConfirmado = false,
    this.duplicidade,
    this.desatualizado = false,
    this.decisaoLocalizacao = SeiDecisaoCampo.pendente,
    this.localizacaoDestinoId,
    this.localizacaoDestinoNome,
    this.decisaoResponsavel = SeiDecisaoCampo.pendente,
    this.responsavelDestino,
  });

  final bool selecionado;

  /// "Conferi o número deste patrimônio no documento original" —
  /// obrigatório para linhas com confiança MÉDIA antes de poderem ser
  /// selecionadas. Nunca promovido automaticamente.
  final bool avisoConfirmado;

  final SeiDuplicidadeResultado? duplicidade;

  /// true quando a revalidação encontrou uma divergência entre o que foi
  /// analisado e o estado atual no InvTec — bloqueia seleção até nova
  /// revisão.
  final bool desatualizado;

  /// Decisão explícita para a localização de destino — o documento SEI
  /// nunca a informa, e `pendente` bloqueia a elegibilidade do item no
  /// plano (nunca resolvido automaticamente pela autorização geral do
  /// documento).
  final SeiDecisaoCampo decisaoLocalizacao;
  final String? localizacaoDestinoId;
  final String? localizacaoDestinoNome;

  /// Idem, para o responsável de destino.
  final SeiDecisaoCampo decisaoResponsavel;
  final String? responsavelDestino;

  SeiItemExecucaoEstado copyWith({
    bool? selecionado,
    bool? avisoConfirmado,
    SeiDuplicidadeResultado? Function()? duplicidade,
    bool? desatualizado,
    SeiDecisaoCampo? decisaoLocalizacao,
    String? Function()? localizacaoDestinoId,
    String? Function()? localizacaoDestinoNome,
    SeiDecisaoCampo? decisaoResponsavel,
    String? Function()? responsavelDestino,
  }) {
    return SeiItemExecucaoEstado(
      selecionado: selecionado ?? this.selecionado,
      avisoConfirmado: avisoConfirmado ?? this.avisoConfirmado,
      duplicidade: duplicidade != null ? duplicidade() : this.duplicidade,
      desatualizado: desatualizado ?? this.desatualizado,
      decisaoLocalizacao: decisaoLocalizacao ?? this.decisaoLocalizacao,
      localizacaoDestinoId: localizacaoDestinoId != null ? localizacaoDestinoId() : this.localizacaoDestinoId,
      localizacaoDestinoNome: localizacaoDestinoNome != null ? localizacaoDestinoNome() : this.localizacaoDestinoNome,
      decisaoResponsavel: decisaoResponsavel ?? this.decisaoResponsavel,
      responsavelDestino: responsavelDestino != null ? responsavelDestino() : this.responsavelDestino,
    );
  }
}
