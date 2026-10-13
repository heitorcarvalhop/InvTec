/// Contagens dos cards principais do Dashboard. Cada campo é `null` quando
/// o usuário atual não tem a permissão correspondente (card omitido da UI
/// — nunca consultado no servidor), e um número (inclusive `0`) quando a
/// consulta foi feita — [DashboardKpisX.nenhumCard] distingue "sem nenhum
/// card visível" de "cards visíveis, todos zerados".
class DashboardKpis {
  const DashboardKpis({
    this.totalPatrimonios,
    this.totalSetores,
    this.totalLocalizacoes,
    this.totalTipos,
    this.movimentacoesUltimos30Dias,
  });

  /// `patrimonio.view`.
  final int? totalPatrimonios;

  /// `setor.view` — contagem de setores ATIVOS.
  final int? totalSetores;

  /// `localizacao.view` — contagem de localizações ATIVAS.
  final int? totalLocalizacoes;

  /// `tipo_patrimonio.view` — contagem de tipos ATIVOS.
  final int? totalTipos;

  /// `movimentacao.view` — movimentações com `data_movimentacao` nos
  /// últimos 30 dias (janela corrida, não "mês calendário").
  final int? movimentacoesUltimos30Dias;
}

extension DashboardKpisX on DashboardKpis {
  bool get nenhumCard =>
      totalPatrimonios == null &&
      totalSetores == null &&
      totalLocalizacoes == null &&
      totalTipos == null &&
      movimentacoesUltimos30Dias == null;
}
