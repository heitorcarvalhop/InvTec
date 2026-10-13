import 'package:invtec/features/dashboard/domain/dashboard_distribuicoes.dart';
import 'package:invtec/features/dashboard/domain/dashboard_repository.dart';
import 'package:invtec/features/dashboard/domain/movimentacao_resumo.dart';

const _distribuicoesVazias = DashboardDistribuicoes(
  porSetor: [],
  porTipo: [],
  topLocalizacoes: [],
  totalConsiderado: 0,
);

/// Fake em memória de [DashboardRepository], sem nenhuma chamada de rede —
/// usado para testar [DashboardPage] isolada do Supabase real. Cada bloco
/// de dados (contagens/distribuição/movimentações) tem seu PRÓPRIO campo de
/// erro — nunca um único `erro` para o repositório inteiro — porque o
/// Dashboard carrega essas três coisas de forma independente (uma falha
/// isolada não pode derrubar as outras seções).
class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({
    this.totalPatrimonios = 0,
    this.totalSetores = 0,
    this.totalLocalizacoes = 0,
    this.totalTipos = 0,
    this.movimentacoesUltimos30Dias = 0,
    this.distribuicoes = _distribuicoesVazias,
    this.movimentacoesRecentes = const [],
    this.erroContagens,
    this.erroDistribuicoes,
    this.erroMovimentacoes,
  });

  final int totalPatrimonios;
  final int totalSetores;
  final int totalLocalizacoes;
  final int totalTipos;
  final int movimentacoesUltimos30Dias;
  final DashboardDistribuicoes distribuicoes;
  final List<MovimentacaoResumo> movimentacoesRecentes;

  final Object? erroContagens;
  final Object? erroDistribuicoes;
  final Object? erroMovimentacoes;

  Future<int> _contagem(int valor) async {
    if (erroContagens != null) throw erroContagens!;
    return valor;
  }

  @override
  Future<int> contarPatrimonios() => _contagem(totalPatrimonios);

  @override
  Future<int> contarSetoresAtivos() => _contagem(totalSetores);

  @override
  Future<int> contarLocalizacoesAtivas() => _contagem(totalLocalizacoes);

  @override
  Future<int> contarTiposAtivos() => _contagem(totalTipos);

  @override
  Future<int> contarMovimentacoesDesde(DateTime desde) => _contagem(movimentacoesUltimos30Dias);

  @override
  Future<DashboardDistribuicoes> carregarDistribuicoes() async {
    if (erroDistribuicoes != null) throw erroDistribuicoes!;
    return distribuicoes;
  }

  @override
  Future<List<MovimentacaoResumo>> listarMovimentacoesRecentes({int limit = 8}) async {
    if (erroMovimentacoes != null) throw erroMovimentacoes!;
    return movimentacoesRecentes;
  }
}
