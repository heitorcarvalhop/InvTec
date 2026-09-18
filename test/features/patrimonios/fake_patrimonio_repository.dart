import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_search_field.dart';
import 'package:invtec/features/patrimonios/domain/patrimonios_resultado.dart';

/// `true` quando [texto] é composto só por dígitos (após `trim`) — mesma
/// regra usada em [PatrimonioRepositorySupabase] (PROMPT 9.1) para decidir,
/// no modo "Tudo", entre identificador exato e texto livre.
bool _somenteDigitos(String texto) => RegExp(r'^\d+$').hasMatch(texto);

bool _contemIgnorandoCaixa(String? valor, String termo) =>
    valor != null && valor.toLowerCase().contains(termo.toLowerCase());

/// Mesmo teto usado em PatrimonioRepositorySupabase (PROMPT 9.1.1).
const _limiteCorrespondenciaSerie = 10;

/// Fake em memória de [PatrimonioRepository], sem nenhuma chamada de rede —
/// usado para testar a listagem/detalhe/formulário isolados do Supabase
/// real. Reproduz as mesmas mensagens amigáveis que o mapper real
/// produziria (número duplicado), para o teste validar o texto exibido.
class FakePatrimonioRepository implements PatrimonioRepository {
  FakePatrimonioRepository({List<PatrimonioDetalhe>? itens, this.erro})
    : _itens = [...?itens];

  final List<PatrimonioDetalhe> _itens;
  final Object? erro;

  int cadastrarCallCount = 0;
  int atualizarCallCount = 0;

  /// Quantas vezes cada consulta em lote foi chamada — usado para provar
  /// que a comparação de tombamentos da planilha com o banco (PROMPT 8.10)
  /// faz UMA chamada por lista, nunca uma consulta por linha/número.
  int buscarPorNumerosPatrimonioCallCount = 0;
  int buscarNumerosSerieExistentesCallCount = 0;

  /// Parâmetros da última chamada a [cadastrar] — usado para verificar o
  /// que foi enviado à "RPC" (ver seção 12 do relatório: nunca status).
  Map<String, Object?>? ultimoCadastro;

  /// Reproduz, em memória, a MESMA semântica de
  /// [PatrimonioRepositorySupabase] para cada [PatrimonioSearchField]
  /// (PROMPT 9.1) — em especial, [PatrimonioSearchField.patrimonio] é
  /// sempre correspondência EXATA, nunca `contains`.
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
        // [listar] (PROMPT 9.1.1: lógica de duas etapas, nunca mistura
        // patrimônio com série no mesmo resultado). Só sobra o ramo
        // textual.
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
  /// releitura posterior (PROMPT 10.2.1, seção 4: concorrência). Nunca usado
  /// pelo app real, só pelos testes.
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

  PatrimoniosResultado _paginar(Iterable<PatrimonioDetalhe> itens, {required int limit, required int offset}) {
    final lista = itens.toList()
      ..sort((a, b) {
        final porData = b.patrimonio.dataCadastro.compareTo(a.patrimonio.dataCadastro);
        return porData != 0 ? porData : b.patrimonio.id.compareTo(a.patrimonio.id);
      });
    final pagina = lista.skip(offset).take(limit).toList();
    return PatrimoniosResultado(itens: pagina, total: lista.length);
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
  }) async {
    if (erro != null) throw erro!;

    final termo = busca?.trim();

    // PROMPT 9.1.1: mesma lógica em duas etapas do repositório real — ver
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
      final resultadoPatrimonio = _paginar(matchPatrimonio, limit: limit, offset: offset);
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
    return _paginar(resultado, limit: limit, offset: offset);
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
}
