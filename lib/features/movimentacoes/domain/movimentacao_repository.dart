import 'movimentacao.dart';
import 'movimentacao_historico_item.dart';
import 'movimentacoes_resultado.dart';

abstract class MovimentacaoRepository {
  /// Histórico paginado de um patrimônio, do mais recente para o mais antigo.
  Future<List<Movimentacao>> listarPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  });

  /// Listagem geral de movimentações (PROMPT 10.1), com busca/filtros e
  /// paginação resolvidos no servidor — mesmo padrão de
  /// [PatrimonioRepository.listar]: uma única consulta com embed (nunca
  /// N+1), ordenada por `data_movimentacao DESC, id DESC`.
  ///
  /// [busca] casa por OR contra número do patrimônio, responsável (origem
  /// OU destino), número de documento e número de chamado. [setorId] casa
  /// contra origem OU destino.
  Future<MovimentacoesResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    MovimentacaoTipo? tipo,
    String? setorId,
    DateTime? periodoDe,
    DateTime? periodoAte,
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
