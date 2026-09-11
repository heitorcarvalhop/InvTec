import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_repository_supabase.dart';
import '../domain/dashboard_stats.dart';
import '../domain/movimentacao_resumo.dart';

class DashboardData {
  const DashboardData({required this.stats, required this.movimentacoesRecentes});

  final DashboardStats stats;
  final List<MovimentacaoResumo> movimentacoesRecentes;
}

/// Carrega estatísticas e movimentações recentes em paralelo. `autoDispose`
/// para não manter dados obsoletos em memória ao sair do dashboard; a UI
/// invalida este provider para implementar "Tentar novamente".
final dashboardDataProvider = FutureProvider.autoDispose<DashboardData>((
  ref,
) async {
  final repository = ref.watch(dashboardRepositoryProvider);

  final results = await Future.wait([
    repository.carregarEstatisticas(),
    repository.listarMovimentacoesRecentes(),
  ]);

  return DashboardData(
    stats: results[0] as DashboardStats,
    movimentacoesRecentes: results[1] as List<MovimentacaoResumo>,
  );
});
