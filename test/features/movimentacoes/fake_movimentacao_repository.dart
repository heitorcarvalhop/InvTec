import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_historico_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_repository.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacoes_resultado.dart';

bool _contemIgnorandoCaixa(String? valor, String termo) =>
    valor != null && valor.toLowerCase().contains(termo.toLowerCase());

/// Fake em memória de [MovimentacaoRepository] — reproduz, em memória, a
/// MESMA semântica de ordenação/filtro/paginação de
/// `MovimentacaoRepositorySupabase.listar` (PROMPT 10.1), para testar o
/// controller/tela isolados do Supabase real.
class FakeMovimentacaoRepository implements MovimentacaoRepository {
  FakeMovimentacaoRepository({
    List<MovimentacaoListagemItem>? itens,
    this.historico = const [],
    this.movimentacaoRegistrada,
    this.erro,
    this.erroRegistrar,
  }) : _itens = [...?itens];

  final List<MovimentacaoListagemItem> _itens;
  final List<MovimentacaoHistoricoItem> historico;
  final Movimentacao? movimentacaoRegistrada;

  /// Erro para [listar] — nunca usado por [registrarMovimentacao] (ver
  /// [erroRegistrar]): os dois precisam poder ser testados
  /// independentemente, sem um teste de listagem acidentalmente também
  /// rejeitar um registro, ou vice-versa.
  final Object? erro;

  /// Erro para [registrarMovimentacao] — simula a RPC rejeitando (transição
  /// inválida, permissão, setor/localização inválidos etc.), nunca a
  /// produção real (PROMPT 10.2, seção 17/18).
  final Object? erroRegistrar;

  int registrarCallCount = 0;

  /// Parâmetros exatos da última chamada a [registrarMovimentacao] — prova
  /// que a UI nunca confunde `null`/vazio/`false` (seção 15 do prompt) e
  /// que a confirmação chama o repository exatamente uma vez com os valores
  /// esperados.
  Map<String, Object?>? ultimoRegistrar;

  /// Filtro/parâmetros da última chamada a [listar] — usado para provar que
  /// a UI está repassando o que o usuário escolheu (sem depender de reler
  /// a tela).
  Map<String, Object?>? ultimaChamadaListar;

  /// Quantas vezes [listar] foi chamado — usado para provar que um registro
  /// bem sucedido recarrega a listagem geral (PROMPT 10.2, seção 12), sem
  /// precisar inspecionar o widget da lista.
  int listarCallCount = 0;

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
  Future<MovimentacoesResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    MovimentacaoTipo? tipo,
    String? setorId,
    DateTime? periodoDe,
    DateTime? periodoAte,
  }) async {
    listarCallCount++;
    ultimaChamadaListar = {
      'limit': limit,
      'offset': offset,
      'busca': busca,
      'tipo': tipo,
      'setorId': setorId,
      'periodoDe': periodoDe,
      'periodoAte': periodoAte,
    };
    if (erro != null) throw erro!;

    Iterable<MovimentacaoListagemItem> resultado = _itens;

    final termo = busca?.trim();
    if (termo != null && termo.isNotEmpty) {
      resultado = resultado.where(
        (item) =>
            _contemIgnorandoCaixa(item.patrimonioNumero, termo) ||
            _contemIgnorandoCaixa(item.responsavelOrigem, termo) ||
            _contemIgnorandoCaixa(item.responsavelDestino, termo) ||
            _contemIgnorandoCaixa(item.numeroDocumento, termo) ||
            _contemIgnorandoCaixa(item.numeroChamado, termo),
      );
    }

    if (tipo != null) {
      resultado = resultado.where((item) => item.tipo == tipo);
    }

    if (setorId != null) {
      resultado = resultado.where((item) => item.setorOrigemId == setorId || item.setorDestinoId == setorId);
    }

    if (periodoDe != null) {
      final inicio = DateTime(periodoDe.year, periodoDe.month, periodoDe.day);
      resultado = resultado.where((item) => !item.dataMovimentacao.isBefore(inicio));
    }
    if (periodoAte != null) {
      final fimExclusivo = DateTime(periodoAte.year, periodoAte.month, periodoAte.day + 1);
      resultado = resultado.where((item) => item.dataMovimentacao.isBefore(fimExclusivo));
    }

    final lista = resultado.toList()
      ..sort((a, b) {
        final porData = b.dataMovimentacao.compareTo(a.dataMovimentacao);
        return porData != 0 ? porData : b.id.compareTo(a.id);
      });

    final pagina = lista.skip(offset).take(limit).toList();
    return MovimentacoesResultado(itens: pagina, total: lista.length);
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
    ultimoRegistrar = {
      'patrimonioId': patrimonioId,
      'tipo': tipo,
      'destinoId': destinoId,
      'localizacaoDestinoId': localizacaoDestinoId,
      'limparLocalizacao': limparLocalizacao,
      'responsavelDestino': responsavelDestino,
      'motivo': motivo,
      'observacao': observacao,
      'numeroDocumento': numeroDocumento,
      'numeroChamado': numeroChamado,
      'dataMovimentacao': dataMovimentacao,
    };
    if (erroRegistrar != null) throw erroRegistrar!;
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
