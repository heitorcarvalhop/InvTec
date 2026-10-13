import 'dashboard_distribuicoes.dart';
import 'movimentacao_resumo.dart';

/// Consultas agregadas (sempre `count`/seleção mínima de colunas — nunca a
/// tabela inteira) usadas pelo Dashboard. Cada contagem é um método
/// próprio (em vez de um único "carregar tudo") para que a camada de
/// apresentação só dispare a consulta cujo card o usuário atual tem
/// permissão de ver — ver `dashboard_providers.dart`.
abstract class DashboardRepository {
  /// `patrimonio.view` — total de patrimônios (todos os status).
  Future<int> contarPatrimonios();

  /// `setor.view` — setores ATIVOS.
  Future<int> contarSetoresAtivos();

  /// `localizacao.view` — localizações ATIVAS.
  Future<int> contarLocalizacoesAtivas();

  /// `tipo_patrimonio.view` — tipos de patrimônio ATIVOS.
  Future<int> contarTiposAtivos();

  /// `movimentacao.view` — movimentações com `data_movimentacao >= desde`.
  Future<int> contarMovimentacoesDesde(DateTime desde);

  /// `patrimonio.view` — distribuição por setor/tipo/localização, numa
  /// única consulta que só lê as colunas de agrupamento (nunca a tabela de
  /// patrimônios inteira, nunca uma consulta por categoria).
  Future<DashboardDistribuicoes> carregarDistribuicoes();

  /// `movimentacao.view` — movimentações mais recentes entre todos os
  /// patrimônios, mais nova primeiro.
  Future<List<MovimentacaoResumo>> listarMovimentacoesRecentes({
    int limit = 8,
  });
}
