import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/patrimonios_resultado.dart';

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

  /// Parâmetros da última chamada a [cadastrar] — usado para verificar o
  /// que foi enviado à "RPC" (ver seção 12 do relatório: nunca status).
  Map<String, Object?>? ultimoCadastro;

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

  @override
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
  }) async {
    if (erro != null) throw erro!;

    Iterable<PatrimonioDetalhe> resultado = _itens;

    final termo = busca?.trim().toLowerCase();
    if (termo != null && termo.isNotEmpty) {
      resultado = resultado.where((item) {
        final p = item.patrimonio;
        return (p.numeroPatrimonio?.toLowerCase().contains(termo) ?? false) ||
            (p.numeroSerie?.toLowerCase().contains(termo) ?? false) ||
            (p.marca?.toLowerCase().contains(termo) ?? false) ||
            (p.modelo?.toLowerCase().contains(termo) ?? false) ||
            (p.descricao?.toLowerCase().contains(termo) ?? false);
      });
    }
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

    final lista = resultado.toList()
      ..sort(
        (a, b) =>
            b.patrimonio.dataCadastro.compareTo(a.patrimonio.dataCadastro),
      );
    final pagina = lista.skip(offset).take(limit).toList();

    return PatrimoniosResultado(itens: pagina, total: lista.length);
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
    if (erro != null) throw erro!;
    final normalizados = numeros.toSet();
    return _itens
        .where((item) => normalizados.contains(item.patrimonio.numeroPatrimonio))
        .toList();
  }

  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) async {
    if (erro != null) throw erro!;
    final procurados = numerosSerie.toSet();
    return _itens
        .map((item) => item.patrimonio.numeroSerie)
        .whereType<String>()
        .where(procurados.contains)
        .toSet();
  }
}
