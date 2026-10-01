import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_situacao.dart';

/// Reproduz exatamente o bug relatado: o Despacho
/// 577/2026/SEMAD/GETEC-12014 (documento SEI 95955192) tinha 33 itens/33
/// pendentes/0 concluídos/0 cancelados CONFIRMADOS por SQL direto na view
/// `documentos_sei_com_situacao`, mas a tabela da aba Pendências mostrava
/// tudo zerado. Causa: `SeiDocumentoPendente.fromJson` sempre recalculava
/// os totais a partir de `itens` (getters), e a consulta de LISTAGEM
/// (`documentos_sei_repository_supabase.dart`, `_colunasListagem`) nunca
/// embeda os itens — só a view manda os totais prontos. Estes testes usam
/// JSON no formato EXATO que a view devolve (chaves `total_itens` etc.,
/// sem a chave `itens`).
Map<String, dynamic> _linhaDaViewSemItens({
  required int totalItens,
  required int totalPendentes,
  required int totalConcluidos,
  required int totalCancelados,
  required String situacao,
}) {
  return {
    'id': '4006bdf4-6927-444e-912b-0e4d42653500',
    'numero_documento_sei': '95955192',
    'numero_processo': '202600017000011',
    'numero_documento_formatado': '577/2026/SEMAD/GETEC-12014',
    'assunto': null,
    'tipo_operacao_pretendida': 'TRANSFERENCIA',
    'nome_arquivo': 'despacho.pdf',
    'hash_sha256': 'hash',
    'versao': 1,
    'criado_em': '2026-09-22T10:00:00Z',
    'criado_por': 'user-1',
    'atualizado_em': null,
    'total_itens': totalItens,
    'total_pendentes': totalPendentes,
    'total_concluidos': totalConcluidos,
    'total_cancelados': totalCancelados,
    'situacao': situacao,
    'autor': {'nome': 'Fulano'},
    // Nunca a chave "itens" aqui — é exatamente isso que falta na consulta
    // real de listagem (a view não embeda itens).
  };
}

void main() {
  group('SeiDocumentoPendente.fromJson (linha de LISTAGEM, sem itens embedados)', () {
    test('Despacho 577 — 33 itens, 33 pendentes, 0 concluídos, 0 cancelados', () {
      final json = _linhaDaViewSemItens(
        totalItens: 33,
        totalPendentes: 33,
        totalConcluidos: 0,
        totalCancelados: 0,
        situacao: 'PENDENTE',
      );

      final documento = SeiDocumentoPendente.fromJson(json);

      expect(documento.totalItens, 33);
      expect(documento.totalPendentes, 33);
      expect(documento.totalConcluidos, 0);
      expect(documento.totalCancelados, 0);
      expect(documento.situacao, SeiDocumentoSituacao.pendente);
      // A listagem nunca embeda itens — a lista fica vazia, mas os
      // CONTADORES (a fonte real do bug) vêm da view, não de `itens`.
      expect(documento.itens, isEmpty);
    });

    test('parcialmente concluído: itens concluídos e cancelados coexistindo com pendentes', () {
      final json = _linhaDaViewSemItens(
        totalItens: 10,
        totalPendentes: 4,
        totalConcluidos: 3,
        totalCancelados: 3,
        situacao: 'PARCIALMENTE_CONCLUIDO',
      );

      final documento = SeiDocumentoPendente.fromJson(json);

      expect(documento.totalItens, 10);
      expect(documento.totalPendentes, 4);
      expect(documento.totalConcluidos, 3);
      expect(documento.totalCancelados, 3);
      expect(documento.situacao, SeiDocumentoSituacao.parcialmenteConcluido);
    });

    test('cancelado: todos os itens cancelados, nada concluído', () {
      final json = _linhaDaViewSemItens(
        totalItens: 5,
        totalPendentes: 0,
        totalConcluidos: 0,
        totalCancelados: 5,
        situacao: 'CANCELADO',
      );

      final documento = SeiDocumentoPendente.fromJson(json);

      expect(documento.totalCancelados, 5);
      expect(documento.situacao, SeiDocumentoSituacao.cancelado);
    });

    test('encerrado parcialmente: concluídos + cancelados, nenhum pendente restante', () {
      final json = _linhaDaViewSemItens(
        totalItens: 8,
        totalPendentes: 0,
        totalConcluidos: 5,
        totalCancelados: 3,
        situacao: 'ENCERRADO_PARCIALMENTE',
      );

      final documento = SeiDocumentoPendente.fromJson(json);

      expect(documento.totalPendentes, 0);
      expect(documento.situacao, SeiDocumentoSituacao.encerradoParcialmente);
    });
  });

  group('SeiDocumentoPendente.fromJson (detalhe, itens embedados) continua correto', () {
    test('totais/situação seguem derivados dos itens quando a chave "itens" está presente', () {
      final json = {
        'id': 'doc-1',
        'numero_documento_sei': '95955192',
        'numero_processo': null,
        'numero_documento_formatado': null,
        'assunto': null,
        'tipo_operacao_pretendida': 'TRANSFERENCIA',
        'nome_arquivo': 'despacho.pdf',
        'hash_sha256': 'hash',
        'versao': 1,
        'criado_em': '2026-09-22T10:00:00Z',
        'criado_por': 'user-1',
        'atualizado_em': null,
        'autor': {'nome': 'Fulano'},
        'itens': [
          for (var i = 1; i <= 3; i++)
            {
              'id': 'item-$i',
              'documento_id': 'doc-1',
              'linha': i,
              'patrimonio_id': null,
              'numero_patrimonio_original': '100$i',
              'numero_patrimonio_corrigido': null,
              'origem_texto_original': 'GETEC',
              'origem_setor_id': null,
              'destino_texto_original': 'GEASI',
              'destino_texto_corrigido': null,
              'destino_setor_id': null,
              'numero_chamado_original': null,
              'numero_chamado_corrigido': null,
              'equipamento_texto_original': 'Monitor',
              'equipamento_texto_corrigido': null,
              'localizacao_destino_id': null,
              'decisao_localizacao': 'CONFIRMADO_SEM_INFORMACAO',
              'responsavel_destino': null,
              'decisao_responsavel': 'CONFIRMADO_SEM_INFORMACAO',
              'status': 'PENDENTE',
              'motivo_cancelamento': null,
              'movimentacao_id': null,
              'corrigido_por': null,
              'corrigido_em': null,
              'motivo_correcao': null,
              'criado_em': '2026-09-22T10:00:00Z',
              'atualizado_em': null,
              'patrimonio': null,
              'origem_setor': null,
              'destino_setor': null,
              'localizacao_destino': null,
              'corretor': null,
            },
        ],
      };

      final documento = SeiDocumentoPendente.fromJson(json);

      expect(documento.itens, hasLength(3));
      expect(documento.totalItens, 3);
      expect(documento.totalPendentes, 3);
      expect(documento.totalConcluidos, 0);
      expect(documento.situacao, SeiDocumentoSituacao.pendente);
    });
  });
}
