import 'package:invtec/core/domain/ordenacao_direcao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_historico_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_ordenacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_repository.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacoes_resultado.dart';

bool _contemIgnorandoCaixa(String? valor, String termo) =>
    valor != null && valor.toLowerCase().contains(termo.toLowerCase());

/// Fake em memória de [MovimentacaoRepository] — reproduz, em memória, a
/// MESMA semântica de ordenação/filtro/paginação de
/// `MovimentacaoRepositorySupabase.listar`, para testar o
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

  /// Só para teste: simula outra movimentação sendo
  /// registrada "por fora" deste fake — ex.: por outro usuário, entre a
  /// análise original e uma revalidação.
  void adicionarMovimentacao(MovimentacaoListagemItem item) => _itens.add(item);

  /// Erro para [listar] — nunca usado por [registrarMovimentacao] (ver
  /// [erroRegistrar]): os dois precisam poder ser testados
  /// independentemente, sem um teste de listagem acidentalmente também
  /// rejeitar um registro, ou vice-versa.
  final Object? erro;

  /// Erro para [registrarMovimentacao] — simula a RPC rejeitando (transição
  /// inválida, permissão, setor/localização inválidos etc.), nunca a
  /// produção real.
  final Object? erroRegistrar;

  int registrarCallCount = 0;

  /// Parâmetros exatos da última chamada a [registrarMovimentacao] — prova
  /// que a UI nunca confunde `null`/vazio/`false` e que a confirmação chama
  /// o repository exatamente uma vez com os valores esperados.
  Map<String, Object?>? ultimoRegistrar;

  /// Filtro/parâmetros da última chamada a [listar] — usado para provar que
  /// a UI está repassando o que o usuário escolheu (sem depender de reler
  /// a tela).
  Map<String, Object?>? ultimaChamadaListar;

  /// Quantas vezes [listar] foi chamado — usado para provar que um registro
  /// bem sucedido recarrega a listagem geral, sem precisar inspecionar o
  /// widget da lista.
  int listarCallCount = 0;

  /// Quantas vezes [listarPorNumeroDocumento] foi chamado — usado para
  /// provar que a checagem de duplicidade do importador SEI faz uma leitura
  /// por análise/revalidação, nunca uma por item (N+1).
  int listarPorNumeroDocumentoCallCount = 0;

  /// Argumentos exatos da última chamada a [listarPorNumeroDocumento].
  Map<String, Object?>? ultimaChamadaListarPorNumeroDocumento;

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
    MovimentacaoOrdenacaoCampo? ordenarPor,
    OrdenacaoDirecao ordenacaoDirecao = OrdenacaoDirecao.asc,
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
      'ordenarPor': ordenarPor,
      'ordenacaoDirecao': ordenacaoDirecao,
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

    final lista = resultado.toList()..sort(_comparadorDe(ordenarPor, ordenacaoDirecao));

    final pagina = lista.skip(offset).take(limit).toList();
    return MovimentacoesResultado(itens: pagina, total: lista.length);
  }

  /// Mesma semântica de
  /// [MovimentacaoRepositorySupabase._aplicarOrdenacao]: `null` mantém o
  /// padrão (`data_movimentacao` mais recente primeiro, `id` como
  /// desempate); qualquer campo escolhido usa `id` como desempate final na
  /// MESMA direção. `patrimonio` compara como TEXTO (nunca numericamente),
  /// igual ao Postgrest real.
  int Function(MovimentacaoListagemItem, MovimentacaoListagemItem) _comparadorDe(
    MovimentacaoOrdenacaoCampo? campo,
    OrdenacaoDirecao direcao,
  ) {
    if (campo == null) {
      return (a, b) {
        final porData = b.dataMovimentacao.compareTo(a.dataMovimentacao);
        return porData != 0 ? porData : b.id.compareTo(a.id);
      };
    }

    final sinal = direcao == OrdenacaoDirecao.asc ? 1 : -1;
    int porCampo(MovimentacaoListagemItem a, MovimentacaoListagemItem b) {
      switch (campo) {
        case MovimentacaoOrdenacaoCampo.data:
          return sinal * a.dataMovimentacao.compareTo(b.dataMovimentacao);
        case MovimentacaoOrdenacaoCampo.patrimonio:
          return _compararNulosPorUltimo(a.patrimonioNumero, b.patrimonioNumero, sinal);
        case MovimentacaoOrdenacaoCampo.tipo:
          return sinal * a.tipo.value.compareTo(b.tipo.value);
        case MovimentacaoOrdenacaoCampo.origem:
          return _compararNulosPorUltimo(a.setorOrigemNome, b.setorOrigemNome, sinal);
        case MovimentacaoOrdenacaoCampo.destino:
          return _compararNulosPorUltimo(a.setorDestinoNome, b.setorDestinoNome, sinal);
      }
    }

    return (a, b) {
      final cmp = porCampo(a, b);
      return cmp != 0 ? cmp : sinal * a.id.compareTo(b.id);
    };
  }

  /// `null` sempre por último, nas duas direções — mesma convenção do
  /// Postgrest real.
  int _compararNulosPorUltimo(String? a, String? b, int sinal) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return sinal * a.compareTo(b);
  }

  @override
  Future<List<MovimentacaoListagemItem>> listarPorNumeroDocumento(
    String numeroDocumento, {
    List<String>? patrimonioIds,
  }) async {
    listarPorNumeroDocumentoCallCount++;
    ultimaChamadaListarPorNumeroDocumento = {'numeroDocumento': numeroDocumento, 'patrimonioIds': patrimonioIds};
    if (erro != null) throw erro!;

    // Reproduz a mesma semântica da implementação real: `eq` exato de
    // numero_documento, nunca substring/OR, e filtro adicional por
    // patrimonioIds quando informado — nunca um limite fixo que descarte
    // linha alguma.
    return _itens
        .where((item) => item.numeroDocumento == numeroDocumento)
        .where((item) => patrimonioIds == null || patrimonioIds.isEmpty || patrimonioIds.contains(item.patrimonioId))
        .toList();
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
