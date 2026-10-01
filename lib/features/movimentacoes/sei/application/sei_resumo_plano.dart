import 'dart:convert';

import '../domain/sei_item_plano.dart';
import '../domain/sei_plano_execucao.dart';

/// Gera um resumo textual (JSON) do plano de execução em memória, para
/// diagnóstico/auditoria — função pura, nenhum efeito colateral, e o plano
/// em si já é somente leitura (nunca chama `registrarMovimentacao`).
String construirResumoPlanoExecucao(SeiPlanoExecucao plano) {
  final mapa = <String, Object?>{
    'totalItens': plano.totalItens,
    'itens': [for (final item in plano.itens) _itemParaMapa(item)],
  };
  return const JsonEncoder.withIndent('  ').convert(mapa);
}

Map<String, Object?> _itemParaMapa(SeiItemPlano item) {
  return {
    'linha': item.linha,
    'numeroPatrimonio': item.numeroPatrimonio,
    'patrimonioId': item.patrimonioId,
    'tipo': item.tipo.name,
    'origemAtual': {'id': item.origemAtualId, 'nome': item.origemAtualNome},
    'destino': {'id': item.destinoId, 'nome': item.destinoNome},
    'localizacaoDestino': {'id': item.localizacaoDestinoId, 'nome': item.localizacaoDestinoNome},
    'responsavelDestino': item.responsavelDestino,
    'motivo': item.motivo,
    'observacao': item.observacao,
    'numeroDocumentoSei': item.numeroDocumentoSei,
    'numeroChamado': item.numeroChamado,
    'statusEsperadoAposOperacao': item.statusEsperadoAposOperacao.name,
    'avisoConfirmado': item.avisoConfirmado,
    'duplicidade': {
      'status': item.duplicidade.status.name,
      'detalhe': item.duplicidade.detalhe,
      'correspondenteId': item.duplicidade.correspondente?.id,
    },
    'pendenciasDecisao': item.pendenciasDecisao,
  };
}
