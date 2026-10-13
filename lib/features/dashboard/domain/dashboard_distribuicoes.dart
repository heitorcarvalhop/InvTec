import 'categoria_contagem.dart';

/// Distribuição de patrimônios por setor/tipo/localização — calculada a
/// partir de UMA única consulta (ver
/// `DashboardRepositorySupabase.carregarDistribuicoes`), nunca uma consulta
/// por categoria.
class DashboardDistribuicoes {
  const DashboardDistribuicoes({
    required this.porSetor,
    required this.porTipo,
    required this.topLocalizacoes,
    required this.totalConsiderado,
  });

  /// Todos os setores com ao menos um patrimônio, do maior para o menor
  /// (poucos setores hoje — sem necessidade de "Top N").
  final List<CategoriaContagem> porSetor;

  /// Os tipos de patrimônio mais frequentes, do maior para o menor — já
  /// recortado para exibição (ver [DashboardRepositorySupabase._topTipos]).
  final List<CategoriaContagem> porTipo;

  /// As localizações com mais patrimônios, do maior para o menor — já
  /// recortado para exibição. Patrimônios sem localização cadastrada não
  /// entram aqui (não há categoria "Sem localização" a ranquear).
  final List<CategoriaContagem> topLocalizacoes;

  /// Total de patrimônios considerado no cálculo (soma de [porSetor]) —
  /// usado para calcular percentuais nas barras.
  final int totalConsiderado;
}
