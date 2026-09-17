import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_historico_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_repository.dart';

class FakeMovimentacaoRepository implements MovimentacaoRepository {
  FakeMovimentacaoRepository({
    this.historico = const [],
    this.movimentacaoRegistrada,
  });

  final List<MovimentacaoHistoricoItem> historico;
  final Movimentacao? movimentacaoRegistrada;
  int registrarCallCount = 0;

  @override
  Future<List<Movimentacao>> listarPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<MovimentacaoHistoricoItem>> listarHistoricoPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  }) async {
    return historico.skip(offset).take(limit).toList();
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
    registrarCallCount++;
    if (movimentacaoRegistrada != null) return movimentacaoRegistrada!;
    return Movimentacao(
      id: 'fake-mov-$registrarCallCount',
      patrimonioId: patrimonioId,
      tipo: tipo,
      destinoId: destinoId,
      localizacaoDestinoId: localizacaoDestinoId,
      responsavelDestino: responsavelDestino,
      motivo: motivo,
      observacao: observacao,
      numeroDocumento: numeroDocumento,
      numeroChamado: numeroChamado,
      dataMovimentacao: dataMovimentacao ?? DateTime.now(),
      criadoEm: DateTime.now(),
    );
  }
}
