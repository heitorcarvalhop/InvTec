import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../../patrimonios/domain/patrimonio.dart';
import '../domain/dashboard_repository.dart';
import '../domain/dashboard_stats.dart';
import '../domain/movimentacao_resumo.dart';

class DashboardRepositorySupabase implements DashboardRepository {
  DashboardRepositorySupabase(this._client);

  final SupabaseClient _client;

  Future<int> _count([String? status]) {
    final query = _client.from('patrimonios').count(CountOption.exact);
    return status == null ? query : query.eq('status', status);
  }

  @override
  Future<DashboardStats> carregarEstatisticas() async {
    try {
      final resultados = await Future.wait([
        _count(),
        _count(PatrimonioStatus.disponivel.value),
        _count(PatrimonioStatus.emUso.value),
        _count(PatrimonioStatus.emprestado.value),
        _count(PatrimonioStatus.emManutencao.value),
        _count(PatrimonioStatus.baixado.value),
      ]);

      final total = resultados[0];
      final baixados = resultados[5];

      return DashboardStats(
        total: total,
        ativos: total - baixados,
        disponiveis: resultados[1],
        emUso: resultados[2],
        emprestados: resultados[3],
        emManutencao: resultados[4],
        baixados: baixados,
      );
    } on PostgrestException catch (e) {
      throw AppException(
        'Falha ao carregar estatísticas do dashboard',
        cause: e,
      );
    }
  }

  @override
  Future<List<MovimentacaoResumo>> listarMovimentacoesRecentes({
    int limit = 5,
  }) async {
    try {
      final rows = await _client
          .from('movimentacoes')
          .select(
            'id, tipo, data_movimentacao, '
            'patrimonios(numero_patrimonio, descricao), '
            'origem:setores!origem_id(nome), '
            'destino:setores!destino_id(nome)',
          )
          .order('data_movimentacao', ascending: false)
          .order('criado_em', ascending: false)
          .limit(limit);

      return rows.map(MovimentacaoResumo.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Falha ao carregar movimentações recentes',
        cause: e,
      );
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositorySupabase(Supabase.instance.client);
});
