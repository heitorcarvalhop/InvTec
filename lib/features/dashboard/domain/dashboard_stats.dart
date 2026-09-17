/// Contagens agregadas de patrimônios para os cards do dashboard.
///
/// [ativos] é "não baixados" (total - baixados), e não "na GETEC": ainda
/// não há setores cadastrados para calcular isso, e inventar um setor fixo
/// aqui seria assumir dado que não existe — ver docs/database.md e a
/// decisão registrada no relatório desta etapa.
class DashboardStats {
  const DashboardStats({
    required this.total,
    required this.ativos,
    required this.disponiveis,
    required this.emUso,
    required this.emprestados,
    required this.emManutencao,
    required this.baixados,
  });

  const DashboardStats.zero()
    : total = 0,
      ativos = 0,
      disponiveis = 0,
      emUso = 0,
      emprestados = 0,
      emManutencao = 0,
      baixados = 0;

  final int total;
  final int ativos;

  /// Contagem de `status = DISPONIVEL` (PROMPT 9.3 — card "Disponíveis" do
  /// dashboard).
  final int disponiveis;
  final int emUso;
  final int emprestados;
  final int emManutencao;
  final int baixados;
}
