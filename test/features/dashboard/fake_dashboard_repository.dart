import 'package:invtec/features/dashboard/domain/dashboard_repository.dart';
import 'package:invtec/features/dashboard/domain/dashboard_stats.dart';
import 'package:invtec/features/dashboard/domain/movimentacao_resumo.dart';

/// Fake em memória de [DashboardRepository], sem nenhuma chamada de rede —
/// usado para testar [DashboardPage] isolada do Supabase real.
class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({
    this.stats = const DashboardStats.zero(),
    this.movimentacoesRecentes = const [],
    this.erro,
  });

  final DashboardStats stats;
  final List<MovimentacaoResumo> movimentacoesRecentes;
  final Object? erro;

  @override
  Future<DashboardStats> carregarEstatisticas() async {
    if (erro != null) throw erro!;
    return stats;
  }

  @override
  Future<List<MovimentacaoResumo>> listarMovimentacoesRecentes({
    int limit = 5,
  }) async {
    if (erro != null) throw erro!;
    return movimentacoesRecentes;
  }
}
