import 'dashboard_stats.dart';
import 'movimentacao_resumo.dart';

abstract class DashboardRepository {
  /// Contagens de patrimônios por status. Usa queries de `count` (sem
  /// carregar linhas) — nunca lista a tabela inteira para contar no Flutter.
  Future<DashboardStats> carregarEstatisticas();

  /// Movimentações mais recentes entre todos os patrimônios, mais nova
  /// primeiro.
  Future<List<MovimentacaoResumo>> listarMovimentacoesRecentes({
    int limit = 5,
  });
}
