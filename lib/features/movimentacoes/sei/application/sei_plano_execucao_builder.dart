import '../../../patrimonios/domain/patrimonio.dart';
import '../domain/sei_analise_resultado.dart';
import '../domain/sei_decisao_campo.dart';
import '../domain/sei_duplicidade.dart';
import '../domain/sei_item_execucao_estado.dart';
import '../domain/sei_item_extraido.dart';
import '../domain/sei_item_plano.dart';
import '../domain/sei_plano_execucao.dart';
import '../domain/sei_validacao_item.dart';

const _duplicidadeAindaNaoVerificada = SeiDuplicidadeResultado(
  status: SeiDuplicidadeStatus.semCorrespondencia,
  detalhe: 'Duplicidade ainda não verificada.',
);

/// Critério único de elegibilidade técnica de um item — usado tanto para
/// decidir se uma linha pode ser SELECIONADA
/// (`SeiImportController.alternarSelecao`) quanto para o que entra no
/// plano (`construirPlanoExecucao`), para as duas nunca divergirem.
///
/// "Documento autorizado" (`SeiImportState.autorizacaoConfirmada`) é uma
/// confirmação GERAL do procedimento — nunca resolve, sozinha, nenhuma
/// pendência individual listada aqui. Um item só é "efetivamente apto"
/// quando TODAS as condições abaixo são satisfeitas.
bool itemEstaApto({required SeiValidacaoItem validacao, required SeiItemExecucaoEstado? estado}) {
  if (validacao.status == SeiStatusLinha.bloqueado) return false;
  if (validacao.destino.entidadeEncontrada == null) return false;

  final e = estado ?? const SeiItemExecucaoEstado();
  if (e.desatualizado) return false;
  if (_exigeConfirmacaoDeAviso(validacao) && !e.avisoConfirmado) return false;

  // Só `semCorrespondencia` é uma checagem "limpa" — qualquer outro
  // veredito (já registrada, possível duplicidade, tipo divergente) exige
  // revisão humana fora desta versão, nunca resolvido pela seleção.
  final duplicidade = e.duplicidade?.status ?? SeiDuplicidadeStatus.semCorrespondencia;
  if (duplicidade != SeiDuplicidadeStatus.semCorrespondencia) return false;

  // Localização e responsável de destino exigem decisão humana explícita —
  // "pendente" bloqueia, mesmo com o documento autorizado.
  if (e.decisaoLocalizacao == SeiDecisaoCampo.pendente) return false;
  if (e.decisaoResponsavel == SeiDecisaoCampo.pendente) return false;

  return true;
}

bool _exigeConfirmacaoDeAviso(SeiValidacaoItem validacao) => validacao.item.confiancaPatrimonio == SeiConfianca.media;

/// Itens tecnicamente aptos a entrar em um lote futuro — independente de já
/// terem sido selecionados ou não (distinto do plano: "itens efetivamente
/// aptos" é uma contagem própria, nunca confundida com "documento
/// autorizado" nem com a seleção atual).
List<SeiValidacaoItem> itensElegiveis({
  required SeiAnaliseResultado resultado,
  required Map<int, SeiItemExecucaoEstado> execucao,
}) {
  return resultado.itens
      .where((validacao) => itemEstaApto(validacao: validacao, estado: execucao[validacao.item.linha]))
      .toList();
}

/// Monta o plano de execução em memória — puramente de leitura: nada aqui,
/// nem em quem o consome, chama `registrarMovimentacao`. Só inclui itens
/// selecionados **e** elegíveis (ver [itemEstaApto]) — mesmo que, por algum
/// estado inconsistente, uma linha não elegível tenha chegado marcada como
/// selecionada (defesa em profundidade: nunca selecionar silenciosamente
/// linhas bloqueadas).
SeiPlanoExecucao construirPlanoExecucao({
  required SeiAnaliseResultado resultado,
  required Map<int, SeiItemExecucaoEstado> execucao,
}) {
  final itens = <SeiItemPlano>[];

  for (final validacao in resultado.itens) {
    final estado = execucao[validacao.item.linha];
    if (estado == null || !estado.selecionado) continue;
    if (!itemEstaApto(validacao: validacao, estado: estado)) continue;

    final patrimonio = validacao.patrimonioEncontrado;
    final numeroPatrimonio = validacao.item.numeroPatrimonio;
    final tipo = resultado.documento.tipoMovimentacaoInferido;
    if (patrimonio == null || numeroPatrimonio == null || tipo == null) continue;

    // Os valores de destino vêm da decisão humana explícita (nunca `null`
    // silencioso) — `itemEstaApto` já garante que nenhuma das duas decisões
    // está pendente neste ponto.
    final responsavelEscolhido = estado.decisaoResponsavel == SeiDecisaoCampo.definido
        ? estado.responsavelDestino
        : null;

    final pendencias = <String>[
      if (estado.decisaoLocalizacao == SeiDecisaoCampo.confirmadoSemInformacao)
        'Localização de destino: confirmado explicitamente que fica sem informação (a RPC gravará null — não '
            'preserva a localização atual para TRANSFERENCIA).',
      if (estado.decisaoResponsavel == SeiDecisaoCampo.confirmadoSemInformacao)
        if (patrimonio.patrimonio.responsavelAtual != null && patrimonio.patrimonio.responsavelAtual!.trim().isNotEmpty)
          'Responsável de destino: confirmado explicitamente sem informação, mesmo o patrimônio tendo responsável '
              'atual ("${patrimonio.patrimonio.responsavelAtual}") — a RPC vai APAGAR o responsável e mudar o '
              'status para Disponível.'
        else
          'Responsável de destino: confirmado explicitamente sem informação — resultaria em status "Disponível".',
    ];

    itens.add(
      SeiItemPlano(
        linha: validacao.item.linha,
        numeroPatrimonio: numeroPatrimonio,
        patrimonioId: patrimonio.patrimonio.id,
        tipo: tipo,
        origemAtualId: patrimonio.patrimonio.setorAtualId,
        origemAtualNome: patrimonio.setorNome,
        destinoId: validacao.destino.entidadeEncontrada?.id,
        destinoNome: validacao.destino.entidadeEncontrada?.nome,
        localizacaoDestinoId: estado.localizacaoDestinoId,
        localizacaoDestinoNome: estado.localizacaoDestinoNome,
        responsavelDestino: responsavelEscolhido,
        motivo: resultado.documento.numeroDocumentoFormatado == null
            ? null
            : 'Despacho SEI ${resultado.documento.numeroDocumentoFormatado}',
        observacao: null,
        numeroDocumentoSei: resultado.documento.numeroDocumentoSei ?? '',
        numeroChamado: validacao.item.numeroChamado,
        statusEsperadoAposOperacao: (responsavelEscolhido != null && responsavelEscolhido.trim().isNotEmpty)
            ? PatrimonioStatus.emUso
            : PatrimonioStatus.disponivel,
        avisoConfirmado: estado.avisoConfirmado,
        duplicidade: estado.duplicidade ?? _duplicidadeAindaNaoVerificada,
        pendenciasDecisao: pendencias,
      ),
    );
  }

  return SeiPlanoExecucao(itens: itens);
}
