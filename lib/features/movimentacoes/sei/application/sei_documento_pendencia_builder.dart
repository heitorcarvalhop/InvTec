import '../domain/sei_analise_resultado.dart';
import '../domain/sei_decisao_campo.dart';
import '../domain/sei_documento_pendente.dart';
import '../domain/sei_item_execucao_estado.dart';
import '../domain/sei_item_pendente.dart';

/// Constrói o rascunho a persistir quando o usuário escolhe "Salvar como
/// pendência" — função pura: nenhum I/O, nunca chama o repositório nem
/// decide se deve haver confirmação de duplicidade (isso é responsabilidade
/// do controller, que lê `DocumentosSeiRepository.buscarPossivelDuplicata`
/// antes de chamar esta função).
///
/// Retorna `null` quando o documento não tem um tipo de movimentação
/// inferido: a estrutura persistente comporta qualquer tipo de operação,
/// mas o parser desta versão só reconhece despachos de TRANSFERENCIA —
/// nunca inventamos um tipo para poder salvar mesmo assim.
SeiDocumentoPendenteRascunho? construirDocumentoPendenteRascunho({
  required SeiAnaliseResultado resultado,
  required Map<int, SeiItemExecucaoEstado> execucao,
}) {
  final tipo = resultado.documento.tipoMovimentacaoInferido;
  if (tipo == null) return null;

  return SeiDocumentoPendenteRascunho(
    numeroDocumentoSei: resultado.documento.numeroDocumentoSei,
    numeroProcesso: resultado.documento.numeroProcesso,
    numeroDocumentoFormatado: resultado.documento.numeroDocumentoFormatado,
    assunto: resultado.documento.assunto,
    tipoOperacaoPretendida: tipo,
    nomeArquivo: resultado.documento.nomeArquivo,
    hashSha256: resultado.documento.hashSha256,
    itens: [
      for (final validacao in resultado.itens)
        SeiItemPendenteRascunho(
          linha: validacao.item.linha,
          patrimonioId: validacao.patrimonioEncontrado?.patrimonio.id,
          numeroPatrimonioOriginal: validacao.item.numeroPatrimonio,
          origemTextoOriginal: validacao.item.unidadeOrigemTexto,
          origemSetorId: validacao.origem.entidadeEncontrada?.id,
          destinoTextoOriginal: validacao.item.unidadeDestinoTexto,
          destinoSetorId: validacao.destino.entidadeEncontrada?.id,
          numeroChamadoOriginal: validacao.item.numeroChamado,
          equipamentoTextoOriginal: validacao.item.equipamento,
          localizacaoDestinoId: (execucao[validacao.item.linha])?.localizacaoDestinoId,
          localizacaoDestinoNome: (execucao[validacao.item.linha])?.localizacaoDestinoNome,
          decisaoLocalizacao: execucao[validacao.item.linha]?.decisaoLocalizacao ?? SeiDecisaoCampo.pendente,
          responsavelDestino: (execucao[validacao.item.linha])?.responsavelDestino,
          decisaoResponsavel: execucao[validacao.item.linha]?.decisaoResponsavel ?? SeiDecisaoCampo.pendente,
        ),
    ],
  );
}
