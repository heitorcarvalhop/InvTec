import 'package:invtec/core/domain/ordenacao_direcao.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_ordenacao.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_search_field.dart';
import 'package:invtec/features/patrimonios/domain/patrimonios_resultado.dart';
import 'package:invtec/features/patrimonios/importacao/domain/comparacao_execucao.dart';

/// Exceção genérica (nunca [AppException]/
/// [ComparacaoExecucaoFalhouException]) usada por [FakePatrimonioRepository]
/// para simular uma falha de REDE (resultado desconhecido) em
/// [FakePatrimonioRepository.aplicarDecisaoComparacao] — o mesmo papel que
/// um `SocketException`/timeout tem contra o Supabase real: nunca uma
/// recusa síncrona do servidor.
class FalhaDeRedeSimulada implements Exception {
  const FalhaDeRedeSimulada();

  @override
  String toString() => 'FalhaDeRedeSimulada (rede — resultado desconhecido)';
}

/// `true` quando [texto] é composto só por dígitos (após `trim`) — mesma
/// regra usada em [PatrimonioRepositorySupabase] para decidir, no modo
/// "Tudo", entre identificador exato e texto livre.
bool _somenteDigitos(String texto) => RegExp(r'^\d+$').hasMatch(texto);

bool _contemIgnorandoCaixa(String? valor, String termo) =>
    valor != null && valor.toLowerCase().contains(termo.toLowerCase());

/// Mesmo teto usado em PatrimonioRepositorySupabase.
const _limiteCorrespondenciaSerie = 10;

/// Fake em memória de [PatrimonioRepository], sem nenhuma chamada de rede —
/// usado para testar a listagem/detalhe/formulário isolados do Supabase
/// real. Reproduz as mesmas mensagens amigáveis que o mapper real
/// produziria (número duplicado), para o teste validar o texto exibido.
class FakePatrimonioRepository implements PatrimonioRepository {
  FakePatrimonioRepository({
    List<PatrimonioDetalhe>? itens,
    this.erro,
    this.errosExecucaoPorPatrimonioId = const {},
    this.operacaoIdsComFalhaDeRedeSemEscrita = const {},
    this.operacaoIdsComRespostaPerdida = const {},
    this.falhaConsultaExecucao = false,
    this.aposEscritaDeExecucao,
    this.autorId = 'user-1',
  }) : _itens = [...?itens];

  final List<PatrimonioDetalhe> _itens;
  final Object? erro;

  /// Quem "executou" cada [aplicarDecisaoComparacao] (grava
  /// como `criado_por`). Mesmo papel de `autorId` em
  /// `FakeDocumentosSeiRepository`.
  final String autorId;

  /// SÓ PARA TESTE — quando definido, [buscarExecucaoComparacaoPorOperacaoId]
  /// compara `criado_por` contra ESTE valor em vez de [autorId]: simula a
  /// sessão ATUAL (no momento da reconciliação/consulta) ser diferente de
  /// quem criou o registro originalmente — mesmo efeito que
  /// `_client.auth.currentUser` mudar entre duas chamadas na implementação
  /// real (verificar se um usuário consegue consultar indevidamente
  /// operações pertencentes a outro usuário).
  String? usuarioAtualParaTeste;

  /// patrimonioId → exceção lançada ANTES de qualquer
  /// escrita em [aplicarDecisaoComparacao] (mesma garantia de
  /// `ComparacaoExecucaoFalhouException`: recusa síncrona, nada gravado).
  final Map<String, Object> errosExecucaoPorPatrimonioId;

  /// operacaoId → simula uma falha de rede ANTES de qualquer escrita (nada
  /// é gravado; um retry com o mesmo operacaoId executa a operação pela
  /// primeira vez de verdade).
  final Set<String> operacaoIdsComFalhaDeRedeSemEscrita;

  /// operacaoId → a escrita é efetivada normalmente (e fica registrada,
  /// pronta para idempotência), mas a chamada LANÇA em vez de devolver —
  /// simula "a resposta se perdeu depois que o servidor já gravou" (seção
  /// 6/9: timeout após gravação efetiva). Um retry com o MESMO operacaoId
  /// encontra a execução já registrada e devolve `jaExecutado: true`, sem
  /// nenhuma nova escrita.
  final Set<String> operacaoIdsComRespostaPerdida;

  /// Simula uma falha de LEITURA em [buscarExecucaoComparacaoPorOperacaoId]
  /// (nunca convertida em `null` — mesma garantia do repositório real).
  final bool falhaConsultaExecucao;

  /// Chamado logo APÓS uma escrita bem-sucedida (antes de devolver o
  /// resultado) — só para o teste de "troca de usuário durante
  /// processamento" provocar deterministicamente a troca no meio de um
  /// lote, sem depender de timing de `Future.wait`.
  final void Function(DecisaoItemParaExecutar decisao)? aposEscritaDeExecucao;

  int cadastrarCallCount = 0;
  int atualizarCallCount = 0;

  /// Quantas vezes [aplicarDecisaoComparacao] foi chamada
  /// (idempotência incluída: uma chamada repetida com o mesmo operacaoId
  /// AINDA conta aqui, mas não soma a [decisoesAplicadas] nem gera uma
  /// segunda escrita — ver o corpo do método).
  int aplicarDecisaoComparacaoCallCount = 0;

  /// Uma entrada por escrita EFETIVA (nunca por retorno idempotente
  /// repetido) — usado para provar tanto "nenhuma chamada de escrita
  /// inesperada" quanto "retry não duplica movimentação/atualização".
  final List<DecisaoItemParaExecutar> decisoesAplicadas = [];

  final Map<String, ResultadoAplicacaoDecisao> _execucoesPorOperacaoId = {};
  final Map<String, String> _criadoPorPorOperacaoId = {};
  final Map<String, DecisaoItemParaExecutar> _decisaoOriginalPorOperacaoId = {};

  /// Quantas vezes cada consulta em lote foi chamada — usado para provar
  /// que a comparação de tombamentos da planilha com o banco faz UMA
  /// chamada por lista, nunca uma consulta por linha/número.
  int buscarPorNumerosPatrimonioCallCount = 0;
  int buscarNumerosSerieExistentesCallCount = 0;

  /// Parâmetros da última chamada a [cadastrar] — usado para verificar o
  /// que foi enviado à "RPC" (nunca status).
  Map<String, Object?>? ultimoCadastro;

  /// Reproduz, em memória, a MESMA semântica de
  /// [PatrimonioRepositorySupabase] para cada [PatrimonioSearchField] — em
  /// especial, [PatrimonioSearchField.patrimonio] é sempre correspondência
  /// EXATA, nunca `contains`.
  bool _casaComBusca(PatrimonioDetalhe item, PatrimonioSearchField campo, String termo) {
    final p = item.patrimonio;
    switch (campo) {
      case PatrimonioSearchField.patrimonio:
        return p.numeroPatrimonio == normalizarNumeroPatrimonio(termo);
      case PatrimonioSearchField.numeroSerie:
        return _contemIgnorandoCaixa(p.numeroSerie, termo);
      case PatrimonioSearchField.equipamentoDescricao:
        return _contemIgnorandoCaixa(p.descricao, termo);
      case PatrimonioSearchField.marcaModelo:
        return _contemIgnorandoCaixa(p.marca, termo) || _contemIgnorandoCaixa(p.modelo, termo);
      case PatrimonioSearchField.responsavel:
        return _contemIgnorandoCaixa(p.responsavelAtual, termo);
      case PatrimonioSearchField.localizacao:
        return _contemIgnorandoCaixa(item.localizacaoNome, termo);
      case PatrimonioSearchField.tudo:
        // consulta só de dígitos nunca chega aqui — interceptada antes, em
        // [listar] (lógica de duas etapas, nunca mistura patrimônio com
        // série no mesmo resultado). Só sobra o ramo textual.
        return p.numeroPatrimonio == normalizarNumeroPatrimonio(termo) ||
            _contemIgnorandoCaixa(p.numeroSerie, termo) ||
            _contemIgnorandoCaixa(p.marca, termo) ||
            _contemIgnorandoCaixa(p.modelo, termo) ||
            _contemIgnorandoCaixa(p.descricao, termo) ||
            _contemIgnorandoCaixa(p.responsavelAtual, termo) ||
            _contemIgnorandoCaixa(item.localizacaoNome, termo);
    }
  }

  @override
  Future<Patrimonio?> buscarPorId(String id) async {
    for (final item in _itens) {
      if (item.patrimonio.id == id) return item.patrimonio;
    }
    return null;
  }

  @override
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id) async {
    for (final item in _itens) {
      if (item.patrimonio.id == id) return item;
    }
    return null;
  }

  /// Substitui (ou adiciona) o item de um id — só para simular, em teste,
  /// outra sessão alterando o patrimônio entre a leitura inicial e uma
  /// releitura posterior (concorrência). Nunca usado pelo app real, só
  /// pelos testes.
  void substituirDetalhe(PatrimonioDetalhe detalhe) {
    final index = _itens.indexWhere((item) => item.patrimonio.id == detalhe.patrimonio.id);
    if (index >= 0) {
      _itens[index] = detalhe;
    } else {
      _itens.add(detalhe);
    }
  }

  @override
  Future<Patrimonio?> buscarPorNumeroPatrimonio(
    String numeroPatrimonio,
  ) async {
    final numero = normalizarNumeroPatrimonio(numeroPatrimonio);
    for (final item in _itens) {
      if (item.patrimonio.numeroPatrimonio == numero) return item.patrimonio;
    }
    return null;
  }

  Iterable<PatrimonioDetalhe> _comFiltrosComuns(
    Iterable<PatrimonioDetalhe> base, {
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
  }) {
    var resultado = base;
    if (tipoId != null) {
      resultado = resultado.where((item) => item.patrimonio.tipoId == tipoId);
    }
    if (status != null) {
      resultado = resultado.where((item) => item.patrimonio.status == status);
    }
    if (setorId != null) {
      resultado = resultado.where(
        (item) => item.patrimonio.setorAtualId == setorId,
      );
    }
    if (semLocalizacao) {
      resultado = resultado.where((item) => item.patrimonio.localizacaoAtualId == null);
    } else if (localizacaoId != null) {
      resultado = resultado.where((item) => item.patrimonio.localizacaoAtualId == localizacaoId);
    }
    final marcaTrim = marca?.trim();
    if (marcaTrim != null && marcaTrim.isNotEmpty) {
      resultado = resultado.where((item) => _contemIgnorandoCaixa(item.patrimonio.marca, marcaTrim));
    }
    final modeloTrim = modelo?.trim();
    if (modeloTrim != null && modeloTrim.isNotEmpty) {
      resultado = resultado.where((item) => _contemIgnorandoCaixa(item.patrimonio.modelo, modeloTrim));
    }
    final responsavelTrim = responsavel?.trim();
    if (responsavelTrim != null && responsavelTrim.isNotEmpty) {
      resultado = resultado.where(
        (item) => _contemIgnorandoCaixa(item.patrimonio.responsavelAtual, responsavelTrim),
      );
    }
    if (dataCadastroDe != null) {
      final inicio = DateTime(dataCadastroDe.year, dataCadastroDe.month, dataCadastroDe.day);
      resultado = resultado.where((item) => !item.patrimonio.dataCadastro.isBefore(inicio));
    }
    if (dataCadastroAte != null) {
      final fimExclusivo = DateTime(dataCadastroAte.year, dataCadastroAte.month, dataCadastroAte.day + 1);
      resultado = resultado.where((item) => item.patrimonio.dataCadastro.isBefore(fimExclusivo));
    }
    if (dataAquisicaoDe != null) {
      final inicio = DateTime(dataAquisicaoDe.year, dataAquisicaoDe.month, dataAquisicaoDe.day);
      resultado = resultado.where(
        (item) => item.patrimonio.dataAquisicao != null && !item.patrimonio.dataAquisicao!.isBefore(inicio),
      );
    }
    if (dataAquisicaoAte != null) {
      final fim = DateTime(dataAquisicaoAte.year, dataAquisicaoAte.month, dataAquisicaoAte.day);
      resultado = resultado.where(
        (item) => item.patrimonio.dataAquisicao != null && !item.patrimonio.dataAquisicao!.isAfter(fim),
      );
    }
    return resultado;
  }

  PatrimoniosResultado _paginar(
    Iterable<PatrimonioDetalhe> itens, {
    required int limit,
    required int offset,
    PatrimonioOrdenacaoCampo? ordenarPor,
    OrdenacaoDirecao ordenacaoDirecao = OrdenacaoDirecao.asc,
  }) {
    final lista = itens.toList()..sort(_comparadorDe(ordenarPor, ordenacaoDirecao));
    final pagina = lista.skip(offset).take(limit).toList();
    return PatrimoniosResultado(itens: pagina, total: lista.length);
  }

  /// Mesma semântica de [PatrimonioRepositorySupabase._aplicarOrdenacao]:
  /// `null` mantém o padrão (`data_cadastro` mais recente primeiro, `id`
  /// como desempate); qualquer campo escolhido usa `id` como desempate final
  /// na MESMA direção. `numeroPatrimonio` compara como TEXTO (nunca
  /// numericamente) — de propósito, para o fake nunca fingir uma ordenação
  /// que o Postgrest real não faz.
  int Function(PatrimonioDetalhe, PatrimonioDetalhe) _comparadorDe(
    PatrimonioOrdenacaoCampo? campo,
    OrdenacaoDirecao direcao,
  ) {
    if (campo == null) {
      return (a, b) {
        final porData = b.patrimonio.dataCadastro.compareTo(a.patrimonio.dataCadastro);
        return porData != 0 ? porData : b.patrimonio.id.compareTo(a.patrimonio.id);
      };
    }

    final sinal = direcao == OrdenacaoDirecao.asc ? 1 : -1;
    int porCampo(PatrimonioDetalhe a, PatrimonioDetalhe b) {
      switch (campo) {
        case PatrimonioOrdenacaoCampo.numeroPatrimonio:
          return _compararNulosPorUltimo(a.patrimonio.numeroPatrimonio, b.patrimonio.numeroPatrimonio, sinal);
        case PatrimonioOrdenacaoCampo.equipamento:
          return _compararNulosPorUltimo(a.tipoNome, b.tipoNome, sinal);
        case PatrimonioOrdenacaoCampo.marca:
          return _compararNulosPorUltimo(a.patrimonio.marca, b.patrimonio.marca, sinal);
        case PatrimonioOrdenacaoCampo.setor:
          return _compararNulosPorUltimo(a.setorNome, b.setorNome, sinal);
        case PatrimonioOrdenacaoCampo.localizacao:
          return _compararNulosPorUltimo(a.localizacaoNome, b.localizacaoNome, sinal);
        case PatrimonioOrdenacaoCampo.status:
          return _compararNulosPorUltimo(a.patrimonio.status.value, b.patrimonio.status.value, sinal);
        case PatrimonioOrdenacaoCampo.criadoEm:
          return sinal * a.patrimonio.dataCadastro.compareTo(b.patrimonio.dataCadastro);
      }
    }

    return (a, b) {
      final cmp = porCampo(a, b);
      return cmp != 0 ? cmp : sinal * a.patrimonio.id.compareTo(b.patrimonio.id);
    };
  }

  /// `null` sempre por último, nas duas direções — mesma convenção do
  /// Postgrest real (`nullsFirst` nunca é usado por este repositório).
  int _compararNulosPorUltimo(String? a, String? b, int sinal) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return sinal * a.compareTo(b);
  }

  @override
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    PatrimonioSearchField campoBusca = PatrimonioSearchField.tudo,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
    PatrimonioOrdenacaoCampo? ordenarPor,
    OrdenacaoDirecao ordenacaoDirecao = OrdenacaoDirecao.asc,
  }) async {
    if (erro != null) throw erro!;

    final termo = busca?.trim();

    // Mesma lógica em duas etapas do repositório real — ver
    // PatrimonioRepositorySupabase._listarTudoNumerico.
    if (termo != null && termo.isNotEmpty && campoBusca == PatrimonioSearchField.tudo && _somenteDigitos(termo)) {
      final numero = normalizarNumeroPatrimonio(termo);
      final matchPatrimonio = _comFiltrosComuns(
        _itens.where((item) => item.patrimonio.numeroPatrimonio == numero),
        tipoId: tipoId,
        status: status,
        setorId: setorId,
        localizacaoId: localizacaoId,
        semLocalizacao: semLocalizacao,
        marca: marca,
        modelo: modelo,
        responsavel: responsavel,
        dataCadastroDe: dataCadastroDe,
        dataCadastroAte: dataCadastroAte,
        dataAquisicaoDe: dataAquisicaoDe,
        dataAquisicaoAte: dataAquisicaoAte,
      );
      final resultadoPatrimonio = _paginar(
        matchPatrimonio,
        limit: limit,
        offset: offset,
        ordenarPor: ordenarPor,
        ordenacaoDirecao: ordenacaoDirecao,
      );
      if (resultadoPatrimonio.total > 0) return resultadoPatrimonio;

      final matchSerie = _comFiltrosComuns(
        _itens.where((item) => item.patrimonio.numeroSerie == termo),
        tipoId: tipoId,
        status: status,
        setorId: setorId,
        localizacaoId: localizacaoId,
        semLocalizacao: semLocalizacao,
        marca: marca,
        modelo: modelo,
        responsavel: responsavel,
        dataCadastroDe: dataCadastroDe,
        dataCadastroAte: dataCadastroAte,
        dataAquisicaoDe: dataAquisicaoDe,
        dataAquisicaoAte: dataAquisicaoAte,
      );
      final resultadoSerie = _paginar(matchSerie, limit: _limiteCorrespondenciaSerie, offset: 0);
      return PatrimoniosResultado(
        itens: const [],
        total: 0,
        correspondenciasPorNumeroSerie: resultadoSerie.itens,
      );
    }

    Iterable<PatrimonioDetalhe> resultado = _itens;
    if (termo != null && termo.isNotEmpty) {
      resultado = resultado.where((item) => _casaComBusca(item, campoBusca, termo));
    }
    resultado = _comFiltrosComuns(
      resultado,
      tipoId: tipoId,
      status: status,
      setorId: setorId,
      localizacaoId: localizacaoId,
      semLocalizacao: semLocalizacao,
      marca: marca,
      modelo: modelo,
      responsavel: responsavel,
      dataCadastroDe: dataCadastroDe,
      dataCadastroAte: dataCadastroAte,
      dataAquisicaoDe: dataAquisicaoDe,
      dataAquisicaoAte: dataAquisicaoAte,
    );
    return _paginar(
      resultado,
      limit: limit,
      offset: offset,
      ordenarPor: ordenarPor,
      ordenacaoDirecao: ordenacaoDirecao,
    );
  }

  @override
  Future<Patrimonio> cadastrar({
    required String tipoId,
    required String destinoId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
  }) async {
    cadastrarCallCount++;
    ultimoCadastro = {
      'tipoId': tipoId,
      'destinoId': destinoId,
      'numeroPatrimonio': numeroPatrimonio,
      'numeroSerie': numeroSerie,
      'marca': marca,
      'modelo': modelo,
      'descricao': descricao,
      'observacao': observacao,
      'dataAquisicao': dataAquisicao,
      'origemId': origemId,
      'localizacaoOrigemId': localizacaoOrigemId,
      'localizacaoDestinoId': localizacaoDestinoId,
      'responsavelOrigem': responsavelOrigem,
      'responsavelDestino': responsavelDestino,
      'motivo': motivo,
      'observacaoMovimentacao': observacaoMovimentacao,
      'dataMovimentacao': dataMovimentacao,
    };

    if (erro != null) throw erro!;

    final numero = normalizarNumeroPatrimonio(numeroPatrimonio);
    if (numero != null &&
        _itens.any((item) => item.patrimonio.numeroPatrimonio == numero)) {
      throw const AppException('Já existe um patrimônio com este número.');
    }

    final responsavel = (responsavelDestino == null || responsavelDestino.trim().isEmpty)
        ? null
        : responsavelDestino.trim();

    final novo = Patrimonio(
      id: 'novo-${_itens.length + 1}',
      numeroPatrimonio: numero,
      numeroSerie: numeroSerie,
      tipoId: tipoId,
      marca: marca,
      modelo: modelo,
      descricao: descricao,
      observacao: observacao,
      status: responsavel == null
          ? PatrimonioStatus.disponivel
          : PatrimonioStatus.emUso,
      setorAtualId: destinoId,
      responsavelAtual: responsavel,
      dataAquisicao: dataAquisicao,
      dataCadastro: DateTime.now(),
      criadoPor: 'fake-user-id',
      atualizadoEm: DateTime.now(),
    );
    _itens.add(
      PatrimonioDetalhe(
        patrimonio: novo,
        tipoNome: 'Tipo Fake',
        setorNome: 'Setor Fake',
      ),
    );
    return novo;
  }

  @override
  Future<Patrimonio> atualizar({
    required String id,
    String? numeroPatrimonio,
    String? numeroSerie,
    required String tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  }) async {
    atualizarCallCount++;
    if (erro != null) throw erro!;

    final index = _itens.indexWhere((item) => item.patrimonio.id == id);
    final atual = _itens[index];
    final atualizado = Patrimonio(
      id: atual.patrimonio.id,
      numeroPatrimonio: normalizarNumeroPatrimonio(numeroPatrimonio),
      numeroSerie: numeroSerie,
      tipoId: tipoId,
      marca: marca,
      modelo: modelo,
      descricao: descricao,
      observacao: observacao,
      status: atual.patrimonio.status,
      setorAtualId: atual.patrimonio.setorAtualId,
      responsavelAtual: atual.patrimonio.responsavelAtual,
      dataAquisicao: dataAquisicao,
      dataCadastro: atual.patrimonio.dataCadastro,
      criadoPor: atual.patrimonio.criadoPor,
      atualizadoEm: DateTime.now(),
    );
    _itens[index] = PatrimonioDetalhe(
      patrimonio: atualizado,
      tipoNome: atual.tipoNome,
      setorNome: atual.setorNome,
      criadoPorNome: atual.criadoPorNome,
    );
    return atualizado;
  }

  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros) async {
    buscarPorNumerosPatrimonioCallCount++;
    if (erro != null) throw erro!;
    final normalizados = numeros.toSet();
    return _itens
        .where((item) => normalizados.contains(item.patrimonio.numeroPatrimonio))
        .toList();
  }

  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) async {
    buscarNumerosSerieExistentesCallCount++;
    if (erro != null) throw erro!;
    final procurados = numerosSerie.toSet();
    return _itens
        .map((item) => item.patrimonio.numeroSerie)
        .whereType<String>()
        .where(procurados.contains)
        .toSet();
  }

  @override
  Future<ResultadoAplicacaoDecisao> aplicarDecisaoComparacao(DecisaoItemParaExecutar decisao) async {
    aplicarDecisaoComparacaoCallCount++;

    // Idempotência (mesma disciplina da RPC real):
    // um operacaoId já processado nunca gera uma nova escrita QUANDO os
    // parâmetros batem com os da primeira vez — quando algum parâmetro
    // relevante (patrimônio, campos, justificativa, versão) diverge, é
    // conflito (`P0041`), nunca reaproveitado silenciosamente.
    final jaExecutado = _execucoesPorOperacaoId[decisao.operacaoId];
    if (jaExecutado != null) {
      final original = _decisaoOriginalPorOperacaoId[decisao.operacaoId]!;
      final identico =
          original.patrimonioId == decisao.patrimonioId &&
          original.versaoEsperada == decisao.versaoEsperada &&
          original.numeroSerie == decisao.numeroSerie &&
          original.marca == decisao.marca &&
          original.modelo == decisao.modelo &&
          original.descricao == decisao.descricao &&
          original.observacao == decisao.observacao &&
          original.novoSetorId == decisao.novoSetorId &&
          original.novaLocalizacaoId == decisao.novaLocalizacaoId &&
          original.justificativa == decisao.justificativa;
      if (!identico) {
        throw falhaDeExecucaoComparacao(
          codigo: 'P0041',
          mensagemDoServidor: 'operacao_id já foi utilizado com parâmetros ou usuário diferentes',
        );
      }
      return ResultadoAplicacaoDecisao(
        patrimonioId: jaExecutado.patrimonioId,
        metadadosAtualizados: jaExecutado.metadadosAtualizados,
        movimentacaoRegistrada: jaExecutado.movimentacaoRegistrada,
        jaExecutado: true,
        movimentacaoId: jaExecutado.movimentacaoId,
        concluidoEm: jaExecutado.concluidoEm,
      );
    }

    if (operacaoIdsComFalhaDeRedeSemEscrita.contains(decisao.operacaoId)) {
      throw const FalhaDeRedeSimulada();
    }

    final erroDeclarado = errosExecucaoPorPatrimonioId[decisao.patrimonioId];
    if (erroDeclarado != null) throw erroDeclarado;

    final index = _itens.indexWhere((item) => item.patrimonio.id == decisao.patrimonioId);
    if (index < 0) {
      throw falhaDeExecucaoComparacao(codigo: 'P0002', mensagemDoServidor: 'Patrimônio não encontrado');
    }
    final atual = _itens[index];
    if (atual.patrimonio.atualizadoEm != decisao.versaoEsperada) {
      throw falhaDeExecucaoComparacao(
        codigo: 'P0040',
        mensagemDoServidor: 'O patrimônio foi alterado por outra operação desde a comparação',
      );
    }

    decisoesAplicadas.add(decisao);

    final metadadosAplicados = atual.patrimonio.copyWith(
      numeroSerie: decisao.numeroSerie,
      marca: decisao.marca,
      modelo: decisao.modelo,
      descricao: decisao.descricao,
      observacao: decisao.observacao,
    );
    // Setor/localização NUNCA passam por `copyWith` (proibido por design —
    // ver o comentário do método real): simula aqui o mesmo efeito que
    // `registrar_movimentacao` teria, incluindo limpar a localização
    // quando o setor muda sem uma localização nova explícita (mesma regra
    // já homologada dentro da RPC real para AJUSTE_INVENTARIO).
    final houveTrocaDeSetor = decisao.novoSetorId != null && decisao.novoSetorId != atual.patrimonio.setorAtualId;
    final novaLocalizacao = decisao.novaLocalizacaoId ?? (houveTrocaDeSetor ? null : atual.patrimonio.localizacaoAtualId);
    final patrimonioAtualizado = Patrimonio(
      id: metadadosAplicados.id,
      numeroPatrimonio: metadadosAplicados.numeroPatrimonio,
      numeroSerie: metadadosAplicados.numeroSerie,
      tipoId: metadadosAplicados.tipoId,
      marca: metadadosAplicados.marca,
      modelo: metadadosAplicados.modelo,
      descricao: metadadosAplicados.descricao,
      observacao: metadadosAplicados.observacao,
      status: metadadosAplicados.status,
      setorAtualId: decisao.novoSetorId ?? metadadosAplicados.setorAtualId,
      localizacaoAtualId: novaLocalizacao,
      responsavelAtual: metadadosAplicados.responsavelAtual,
      dataAquisicao: metadadosAplicados.dataAquisicao,
      dataCadastro: metadadosAplicados.dataCadastro,
      criadoPor: metadadosAplicados.criadoPor,
      atualizadoEm: DateTime.now(),
    );

    _itens[index] = PatrimonioDetalhe(
      patrimonio: patrimonioAtualizado,
      tipoNome: atual.tipoNome,
      setorNome: atual.setorNome,
      setorSigla: atual.setorSigla,
      localizacaoNome: decisao.novaLocalizacaoId != null ? 'Localização fake' : atual.localizacaoNome,
      criadoPorNome: atual.criadoPorNome,
    );

    final resultado = ResultadoAplicacaoDecisao(
      patrimonioId: decisao.patrimonioId,
      metadadosAtualizados: decisao.temMetadado,
      movimentacaoRegistrada: decisao.temMovimentacao,
      jaExecutado: false,
      movimentacaoId: decisao.temMovimentacao ? 'movimentacao-fake-${decisao.operacaoId}' : null,
      concluidoEm: DateTime.now(),
    );
    _execucoesPorOperacaoId[decisao.operacaoId] = resultado;
    _criadoPorPorOperacaoId[decisao.operacaoId] = autorId;
    _decisaoOriginalPorOperacaoId[decisao.operacaoId] = decisao;
    aposEscritaDeExecucao?.call(decisao);

    if (operacaoIdsComRespostaPerdida.contains(decisao.operacaoId)) {
      throw const FalhaDeRedeSimulada();
    }

    return resultado;
  }

  @override
  Future<ResultadoAplicacaoDecisao?> buscarExecucaoComparacaoPorOperacaoId(String operacaoId) async {
    if (falhaConsultaExecucao) {
      throw const AppException('Falha ao consultar o resultado da operação');
    }
    final resultado = _execucoesPorOperacaoId[operacaoId];
    if (resultado == null) return null;
    // Mesma defesa da implementação real: uma leitura NUNCA é aceita como
    // "a resposta da minha tentativa" quando o `criado_por` gravado não
    // bate com a sessão atual.
    final usuarioAtual = usuarioAtualParaTeste ?? autorId;
    if (_criadoPorPorOperacaoId[operacaoId] != usuarioAtual) {
      throw const AppException('A operação não pertence à sessão atual.');
    }
    return resultado;
  }
}
