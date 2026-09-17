import 'movimentacao.dart';
import 'movimentacao_historico_item.dart';

abstract class MovimentacaoRepository {
  /// Histórico paginado de um patrimônio, do mais recente para o mais antigo.
  Future<List<Movimentacao>> listarPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  });

  /// Igual a [listarPorPatrimonio], mas já traz os nomes de setor/localização
  /// de origem e destino resolvidos (via embed) para exibir a timeline da
  /// tela de detalhe do patrimônio sem consultas extras por linha.
  Future<List<MovimentacaoHistoricoItem>> listarHistoricoPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  });

  /// Registra uma movimentação chamando a função transacional
  /// `registrar_movimentacao` no Postgres, que também atualiza setor,
  /// responsável e status do patrimônio de forma atômica. Origem e
  /// responsável de origem são lidos do estado atual no banco.
  ///
  /// [localizacaoDestinoId] null significa "preservar a localização atual"
  /// — para AJUSTE_INVENTARIO, use [limparLocalizacao] = true para
  /// explicitamente marcar a localização como Não informada (os dois nunca
  /// podem ser usados juntos).
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
  });
}
