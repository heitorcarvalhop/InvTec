import 'movimentacao.dart';

abstract class MovimentacaoRepository {
  /// Histórico paginado de um patrimônio, do mais recente para o mais antigo.
  Future<List<Movimentacao>> listarPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  });

  /// Registra uma movimentação chamando a função transacional
  /// `registrar_movimentacao` no Postgres, que também atualiza setor,
  /// responsável e status do patrimônio de forma atômica. Origem e
  /// responsável de origem são lidos do estado atual no banco.
  Future<Movimentacao> registrarMovimentacao({
    required String patrimonioId,
    required MovimentacaoTipo tipo,
    String? destinoId,
    String? responsavelDestino,
    String? motivo,
    String? observacao,
    String? numeroDocumento,
    String? numeroChamado,
    DateTime? dataMovimentacao,
  });
}
