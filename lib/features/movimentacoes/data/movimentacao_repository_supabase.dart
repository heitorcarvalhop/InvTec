import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/movimentacao.dart';
import '../domain/movimentacao_historico_item.dart';
import '../domain/movimentacao_repository.dart';

class MovimentacaoRepositorySupabase implements MovimentacaoRepository {
  MovimentacaoRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Movimentacao>> listarPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client
          .from('movimentacoes')
          .select()
          .eq('patrimonio_id', patrimonioId)
          .order('data_movimentacao', ascending: false)
          .order('criado_em', ascending: false)
          .range(offset, offset + limit - 1);

      return rows.map(Movimentacao.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Falha ao listar movimentações do patrimônio',
        cause: e,
      );
    }
  }

  @override
  Future<List<MovimentacaoHistoricoItem>> listarHistoricoPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client
          .from('movimentacoes')
          .select(
            'id, tipo, data_movimentacao, responsavel_origem, responsavel_destino, motivo, observacao, '
            'setor_origem:setores!origem_id(nome), '
            'setor_destino:setores!destino_id(nome), '
            'localizacao_origem:localizacoes!localizacao_origem_id(nome), '
            'localizacao_destino:localizacoes!localizacao_destino_id(nome)',
          )
          .eq('patrimonio_id', patrimonioId)
          .order('data_movimentacao', ascending: false)
          .order('criado_em', ascending: false)
          .range(offset, offset + limit - 1);

      return rows.map(MovimentacaoHistoricoItem.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Falha ao carregar o histórico de movimentações do patrimônio',
        cause: e,
      );
    }
  }

  @override
  Future<Movimentacao> registrarMovimentacao({
    required String patrimonioId,
    required MovimentacaoTipo tipo,
    String? destinoId,
    String? localizacaoDestinoId,
    bool limparLocalizacao = false,
    String? responsavelDestino,
    String? motivo,
    String? observacao,
    String? numeroDocumento,
    String? numeroChamado,
    DateTime? dataMovimentacao,
  }) async {
    try {
      final row = await _client.rpc(
        'registrar_movimentacao',
        params: {
          'p_patrimonio_id': patrimonioId,
          'p_tipo': tipo.value,
          'p_destino_id': destinoId,
          'p_responsavel_destino': responsavelDestino,
          'p_motivo': motivo,
          'p_observacao': observacao,
          'p_numero_documento': numeroDocumento,
          'p_numero_chamado': numeroChamado,
          if (dataMovimentacao != null)
            'p_data_movimentacao': dataMovimentacao.toIso8601String(),
          'p_localizacao_destino_id': localizacaoDestinoId,
          'p_limpar_localizacao': limparLocalizacao,
        },
      );
      return Movimentacao.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw AppException('Falha ao registrar movimentação', cause: e);
    }
  }
}

final movimentacaoRepositoryProvider = Provider<MovimentacaoRepository>((
  ref,
) {
  return MovimentacaoRepositorySupabase(Supabase.instance.client);
});
