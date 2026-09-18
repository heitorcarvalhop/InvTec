import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';

/// Testa só a montagem dos parâmetros da RPC (função pura, sem
/// `SupabaseClient`) — nunca chama produção, nunca precisa de um client de
/// verdade (PROMPT 10.2.3).
void main() {
  group('PROMPT 10.2.3 — buildRegistrarMovimentacaoParams: normalização de campos opcionais', () {
    test('motivo/observacao/numero_documento/numero_chamado/responsavel_destino vazios viram null', () {
      final params = buildRegistrarMovimentacaoParams(
        patrimonioId: 'p1',
        tipo: MovimentacaoTipo.manutencao,
        destinoId: 'setor-b',
        responsavelDestino: '',
        motivo: '',
        observacao: '',
        numeroDocumento: '',
        numeroChamado: '',
      );

      expect(params['p_responsavel_destino'], isNull);
      expect(params['p_motivo'], isNull);
      expect(params['p_observacao'], isNull);
      expect(params['p_numero_documento'], isNull);
      expect(params['p_numero_chamado'], isNull);
    });

    test('somente espaços também vira null', () {
      final params = buildRegistrarMovimentacaoParams(
        patrimonioId: 'p1',
        tipo: MovimentacaoTipo.manutencao,
        destinoId: 'setor-b',
        responsavelDestino: '   ',
        motivo: '   ',
        observacao: '  \t ',
        numeroDocumento: '   ',
        numeroChamado: '   ',
      );

      expect(params['p_responsavel_destino'], isNull);
      expect(params['p_motivo'], isNull);
      expect(params['p_observacao'], isNull);
      expect(params['p_numero_documento'], isNull);
      expect(params['p_numero_chamado'], isNull);
    });

    test('texto com espaços nas pontas é aparado antes de enviar', () {
      final params = buildRegistrarMovimentacaoParams(
        patrimonioId: 'p1',
        tipo: MovimentacaoTipo.manutencao,
        destinoId: 'setor-b',
        responsavelDestino: ' Maria Souza ',
        motivo: ' Troca de equipamento ',
        observacao: ' Observação relevante ',
        numeroDocumento: ' DOC-9 ',
        numeroChamado: ' CH-42 ',
      );

      expect(params['p_responsavel_destino'], 'Maria Souza');
      expect(params['p_motivo'], 'Troca de equipamento');
      expect(params['p_observacao'], 'Observação relevante');
      expect(params['p_numero_documento'], 'DOC-9');
      expect(params['p_numero_chamado'], 'CH-42');
    });

    test('texto válido sem espaços extras é preservado', () {
      final params = buildRegistrarMovimentacaoParams(
        patrimonioId: 'p1',
        tipo: MovimentacaoTipo.manutencao,
        destinoId: 'setor-b',
        responsavelDestino: 'João Silva',
        motivo: 'Motivo direto',
        observacao: 'Observação direta',
        numeroDocumento: 'DOC-1',
        numeroChamado: 'CH-1',
      );

      expect(params['p_responsavel_destino'], 'João Silva');
      expect(params['p_motivo'], 'Motivo direto');
      expect(params['p_observacao'], 'Observação direta');
      expect(params['p_numero_documento'], 'DOC-1');
      expect(params['p_numero_chamado'], 'CH-1');
    });

    test('campos já null continuam null (nunca vira "" nem lança erro)', () {
      final params = buildRegistrarMovimentacaoParams(
        patrimonioId: 'p1',
        tipo: MovimentacaoTipo.baixa,
      );

      expect(params['p_responsavel_destino'], isNull);
      expect(params['p_motivo'], isNull);
      expect(params['p_observacao'], isNull);
      expect(params['p_numero_documento'], isNull);
      expect(params['p_numero_chamado'], isNull);
    });

    test('destinoId e localizacaoDestinoId nunca passam por nullIfBlank — são ids, não texto livre', () {
      final params = buildRegistrarMovimentacaoParams(
        patrimonioId: 'p1',
        tipo: MovimentacaoTipo.manutencao,
        destinoId: 'setor-b',
        localizacaoDestinoId: 'loc-b1',
      );

      expect(params['p_destino_id'], 'setor-b');
      expect(params['p_localizacao_destino_id'], 'loc-b1');
    });

    test('demais parâmetros (id, tipo, destino, localização, limpar, data) continuam intactos', () {
      final data = DateTime(2026, 3, 1, 10, 30);
      final params = buildRegistrarMovimentacaoParams(
        patrimonioId: 'p1',
        tipo: MovimentacaoTipo.ajusteInventario,
        destinoId: null,
        localizacaoDestinoId: 'loc-a1',
        limparLocalizacao: false,
        dataMovimentacao: data,
      );

      expect(params['p_patrimonio_id'], 'p1');
      expect(params['p_tipo'], 'AJUSTE_INVENTARIO');
      expect(params['p_destino_id'], isNull);
      expect(params['p_localizacao_destino_id'], 'loc-a1');
      expect(params['p_limpar_localizacao'], isFalse);
      expect(params['p_data_movimentacao'], data.toIso8601String());
    });
  });
}
