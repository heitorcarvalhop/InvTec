import 'dart:convert';

import '../domain/sei_analise_resultado.dart';
import '../domain/sei_validacao_item.dart';

/// Gera um resumo textual (JSON) da análise para fins de DIAGNÓSTICO/auditoria
/// (PROMPT 11.1.1, seção 10) — só leitura, pura, sem nenhum efeito colateral.
/// Contém metadados do documento, o hash SHA-256 (em memória, nunca
/// persistido), cada item extraído e seu veredito (checks/avisos/bloqueios).
/// Nunca inclui dado sensível: nenhum token, credencial ou dado pessoal além
/// do que já está no próprio PDF (nome do responsável/setor, já público no
/// documento SEI original).
String construirResumoDiagnosticoSei(SeiAnaliseResultado resultado) {
  final documento = resultado.documento;

  final mapa = <String, Object?>{
    'documento': {
      'nomeArquivo': documento.nomeArquivo,
      'tamanhoBytes': documento.tamanhoBytes,
      'quantidadePaginas': documento.quantidadePaginas,
      'hashSha256': documento.hashSha256,
      'numeroProcesso': documento.numeroProcesso,
      'numeroDocumentoSei': documento.numeroDocumentoSei,
      'numeroDocumentoFormatado': documento.numeroDocumentoFormatado,
      'assunto': documento.assunto,
      'signatario': documento.signatario,
      'tipoMovimentacaoInferido': documento.tipoMovimentacaoInferido?.name,
      'avisosDoDocumento': documento.avisos,
    },
    'contadores': {
      'totalItens': resultado.totalItens,
      'totalProntos': resultado.totalProntos,
      'totalAvisos': resultado.totalAvisos,
      'totalBloqueados': resultado.totalBloqueados,
    },
    'itens': [for (final item in resultado.itens) _itemParaMapa(item)],
  };

  return const JsonEncoder.withIndent('  ').convert(mapa);
}

Map<String, Object?> _itemParaMapa(SeiValidacaoItem validacao) {
  final item = validacao.item;
  return {
    'linha': item.linha,
    'paginaOrigem': item.paginaOrigem,
    'status': validacao.status.name,
    'numeroPatrimonio': item.numeroPatrimonio,
    'confiancaPatrimonio': item.confiancaPatrimonio.name,
    'equipamento': item.equipamento,
    'numeroChamado': item.numeroChamado,
    'origem': {
      'textoDoDocumento': validacao.origem.valorOriginal,
      'siglaDetectada': validacao.origem.valorNormalizado,
      'setorEncontradoNoInvTec': validacao.origem.entidadeEncontrada?.nome,
    },
    'destino': {
      'textoDoDocumento': validacao.destino.valorOriginal,
      'siglaDetectada': validacao.destino.valorNormalizado,
      'setorEncontradoNoInvTec': validacao.destino.entidadeEncontrada?.nome,
    },
    'equipamentoCompativelComCadastro': validacao.equipamentoCompativel,
    'checks': validacao.checks,
    'avisos': validacao.avisos,
    'bloqueios': validacao.bloqueios,
  };
}
