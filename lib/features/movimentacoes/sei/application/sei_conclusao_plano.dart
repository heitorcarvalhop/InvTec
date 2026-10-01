import '../../../patrimonios/domain/patrimonio.dart';
import '../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../domain/movimentacao.dart';
import '../domain/sei_decisao_campo.dart';
import '../domain/sei_documento_pendente.dart';
import '../domain/sei_item_pendente.dart';

/// Texto mostrado quando um destino foi CONFIRMADO sem informação (a RPC envia
/// null de propósito).
const textoNaoInformado = 'Não informado';

/// Texto mostrado quando ainda NÃO existe decisão (PENDENTE). É diferente de
/// [textoNaoInformado]: PENDENTE não é "confirmado sem informação" — não vira
/// null operacional, não gera consequência e bloqueia a conclusão.
const textoPendenteDeDefinicao = 'Pendente de definição';

/// Texto da situação resultante quando ela depende de uma decisão pendente.
const textoSituacaoIndeterminada = 'Ainda não pode ser determinada';

/// O que a conclusão de UM item vai fazer, calculado só com dados que a tela
/// já tem (PROMPT 11.4.3) — PURO, sem I/O. Alimenta o diálogo de confirmação:
/// o resumo, as consequências que exigem confirmação explícita e os
/// bloqueios já conhecidos. A autoridade final continua sendo a RPC
/// `concluir_item_documento_sei`; isto só evita chamadas que ela recusaria e
/// mostra ao usuário, ANTES de confirmar, o que vai acontecer.
class SeiPlanoConclusao {
  const SeiPlanoConclusao({
    required this.numeroPatrimonio,
    required this.equipamento,
    required this.origemAtual,
    required this.origemDoDocumento,
    required this.destinoSetor,
    required this.decisaoLocalizacao,
    required this.destinoLocalizacao,
    required this.decisaoResponsavel,
    required this.destinoResponsavel,
    required this.numeroDocumento,
    required this.numeroChamado,
    required this.statusResultante,
    required this.localizacaoAtual,
    required this.responsavelAtual,
    required this.limpaLocalizacao,
    required this.limpaResponsavel,
    required this.bloqueios,
  });

  final String numeroPatrimonio;
  final String? equipamento;

  /// Setor em que o patrimônio está AGORA (relido do banco), quando conhecido.
  final String? origemAtual;

  /// Setor de origem que o documento indicava.
  final String? origemDoDocumento;

  final String destinoSetor;

  /// As decisões são tratadas separadamente dos valores: `destinoLocalizacao`/
  /// `destinoResponsavel` só têm significado conforme a decisão.
  ///  - PENDENTE: valor INDEFINIDO ([localizacaoPendente]/[responsavelPendente]);
  ///    o valor é sempre `null`, mas NÃO é um null confirmado.
  ///  - DEFINIDO: o valor escolhido.
  ///  - CONFIRMADO_SEM_INFORMACAO: `null` de propósito ([textoNaoInformado]).
  final SeiDecisaoCampo decisaoLocalizacao;
  final String? destinoLocalizacao;
  final SeiDecisaoCampo decisaoResponsavel;
  final String? destinoResponsavel;

  bool get localizacaoPendente => decisaoLocalizacao == SeiDecisaoCampo.pendente;
  bool get responsavelPendente => decisaoResponsavel == SeiDecisaoCampo.pendente;

  final String? numeroDocumento;
  final String? numeroChamado;

  /// Situação em que o patrimônio ficará (responsável nulo confirmado =>
  /// Disponível). `null` = ainda não pode ser determinada (alguma decisão está
  /// PENDENTE, ou o responsável definido veio sem valor).
  final PatrimonioStatus? statusResultante;

  final String? localizacaoAtual;
  final String? responsavelAtual;

  /// A conclusão apagará uma localização/responsável que HOJE têm valor:
  /// exige confirmação adicional e explícita do usuário
  /// (`p_confirmar_limpeza_destino`). SÓ existe quando a decisão é
  /// CONFIRMADO_SEM_INFORMACAO: uma decisão PENDENTE jamais gera consequência
  /// destrutiva.
  final bool limpaLocalizacao;
  final bool limpaResponsavel;

  /// Motivos que impedem confirmar (lista vazia = pode prosseguir).
  final List<String> bloqueios;

  bool get exigeConfirmacaoDeLimpeza => limpaLocalizacao || limpaResponsavel;
  bool get podeConfirmar => bloqueios.isEmpty;
}

/// Monta o [SeiPlanoConclusao] de [item] contra o estado ATUAL do patrimônio
/// ([patrimonioAtual], `null` quando ainda não foi carregado ou não existe).
SeiPlanoConclusao planejarConclusaoEntrega({
  required SeiDocumentoPendente documento,
  required SeiItemPendente item,
  required PatrimonioDetalhe? patrimonioAtual,
}) {
  final atual = patrimonioAtual?.patrimonio;
  final numero = item.numeroPatrimonio.valorEfetivo ?? '—';

  final decisaoLocalizacao = item.decisaoLocalizacao;
  final decisaoResponsavel = item.decisaoResponsavel;
  final localizacaoDefinida = decisaoLocalizacao == SeiDecisaoCampo.definido;
  final responsavelTexto = (item.responsavelDestino ?? '').trim();
  final responsavelDefinido = decisaoResponsavel == SeiDecisaoCampo.definido && responsavelTexto.isNotEmpty;
  // DEFINIDO sem valor é incoerente: não vira "sem informação" por conta própria.
  final responsavelIncoerente = decisaoResponsavel == SeiDecisaoCampo.definido && responsavelTexto.isEmpty;

  final localizacaoDestino = localizacaoDefinida ? (item.localizacaoDestinoNome ?? 'Localização definida') : null;
  final responsavelDestino = responsavelDefinido ? responsavelTexto : null;

  final responsavelAtual = (atual?.responsavelAtual ?? '').trim().isEmpty ? null : atual!.responsavelAtual!.trim();
  final tinhaLocalizacao = atual?.localizacaoAtualId != null;

  // Só um "sem informação" CONFIRMADO apaga algo.
  final limpaLocalizacao = decisaoLocalizacao == SeiDecisaoCampo.confirmadoSemInformacao && tinhaLocalizacao;
  final limpaResponsavel = decisaoResponsavel == SeiDecisaoCampo.confirmadoSemInformacao && responsavelAtual != null;

  final PatrimonioStatus? statusResultante = responsavelDefinido
      ? PatrimonioStatus.emUso
      : decisaoResponsavel == SeiDecisaoCampo.confirmadoSemInformacao
      ? PatrimonioStatus.disponivel
      : null;

  final bloqueios = <String>[];
  if (documento.tipoOperacaoPretendida != MovimentacaoTipo.transferencia) {
    bloqueios.add('Esta versão só conclui entregas de transferência entre setores.');
  }
  if (item.patrimonioId == null) {
    bloqueios.add(
      'O item não está vinculado a um patrimônio. Corrija o número do patrimônio pela edição do documento.',
    );
  }
  if (item.destinoSetorId == null) {
    bloqueios.add('O setor de destino ainda não foi definido. Corrija pela edição do documento.');
  }
  if (item.decisaoLocalizacao == SeiDecisaoCampo.pendente) {
    bloqueios.add('Defina a localização de destino (pela edição do documento).');
  }
  if (item.decisaoResponsavel == SeiDecisaoCampo.pendente) {
    bloqueios.add('Defina o responsável de destino (pela edição do documento).');
  }
  if (responsavelIncoerente) {
    bloqueios.add(
      'O responsável de destino está marcado como definido, mas sem valor. Corrija pela edição do documento.',
    );
  }
  if (item.patrimonioId != null && patrimonioAtual == null) {
    bloqueios.add('Não foi possível carregar a situação atual do patrimônio. Feche e tente novamente.');
  }
  if (atual != null) {
    if (item.origemSetorId == null) {
      bloqueios.add('O item não tem setor de origem resolvido: não é possível confirmar a situação do patrimônio.');
    } else if (atual.setorAtualId != item.origemSetorId) {
      bloqueios.add(
        'Origem divergente: o patrimônio está hoje em ${patrimonioAtual!.setorNome}, '
        'mas o documento indica outra origem. Revise o patrimônio antes de concluir.',
      );
    }
    if (atual.status != PatrimonioStatus.disponivel && atual.status != PatrimonioStatus.emUso) {
      bloqueios.add('O patrimônio está "${atual.status.label}" e não pode ser transferido.');
    }
    if (item.destinoSetorId != null &&
        item.destinoSetorId == atual.setorAtualId &&
        decisaoLocalizacao == SeiDecisaoCampo.confirmadoSemInformacao) {
      bloqueios.add(
        'Movimentação dentro do mesmo setor exige uma localização de destino definida. '
        '"Sem informação" não é aceito nesse caso.',
      );
    }
  }

  return SeiPlanoConclusao(
    numeroPatrimonio: numero,
    equipamento: item.equipamentoTexto.valorEfetivo,
    origemAtual: patrimonioAtual?.setorNome,
    origemDoDocumento: item.origemSetorNome ?? item.origemTexto.valorEfetivo,
    destinoSetor: item.destinoSetorNome ?? item.destinoTexto.valorEfetivo ?? '—',
    decisaoLocalizacao: decisaoLocalizacao,
    destinoLocalizacao: localizacaoDestino,
    decisaoResponsavel: decisaoResponsavel,
    destinoResponsavel: responsavelDestino,
    numeroDocumento: documento.numeroDocumentoFormatado ?? documento.numeroDocumentoSei,
    numeroChamado: item.numeroChamado.valorEfetivo,
    statusResultante: statusResultante,
    localizacaoAtual: patrimonioAtual?.localizacaoNome,
    responsavelAtual: responsavelAtual,
    limpaLocalizacao: limpaLocalizacao,
    limpaResponsavel: limpaResponsavel,
    bloqueios: bloqueios,
  );
}
