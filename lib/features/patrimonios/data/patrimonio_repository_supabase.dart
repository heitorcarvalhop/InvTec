import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/postgrest_filter.dart';
import '../domain/patrimonio.dart';
import '../domain/patrimonio_detalhe.dart';
import '../domain/patrimonio_repository.dart';
import '../domain/patrimonio_search_field.dart';
import '../domain/patrimonios_resultado.dart';
import 'patrimonio_error_mapper.dart';

/// `true` quando [texto] é composto só por dígitos (após `trim`) — usado
/// pelo modo [PatrimonioSearchField.tudo] (PROMPT 9.1) para decidir entre
/// tratar a busca como identificador exato (`numero_patrimonio`/
/// `numero_serie`) ou como texto livre. Nunca confundir com "parece um
/// número" de forma aproximada — é uma checagem estrita de dígitos.
bool _somenteDigitos(String texto) => RegExp(r'^\d+$').hasMatch(texto);

/// Teto de itens em [PatrimoniosResultado.correspondenciasPorNumeroSerie]
/// (PROMPT 9.1.1) — é só um aviso auxiliar na UI (nunca a listagem
/// principal), não precisa de paginação própria.
const _limiteCorrespondenciaSerie = 10;

/// Colunas de `patrimonios` + os relacionamentos exibidos na interface, sem
/// consulta adicional por linha (uma única viagem ao Postgrest via embed).
/// Só há uma FK de `patrimonios` para `tipos_patrimonio`/`setores`, então
/// não há ambiguidade a desambiguar (diferente de `movimentacoes`, que tem
/// duas FKs para `setores`).
const _colunasComRelacionamentos =
    '*, tipos_patrimonio(nome), setores(nome), localizacoes(nome)';

/// Agrupa os filtros combináveis por AND de [PatrimonioRepositorySupabase.listar]
/// (PROMPT 9.2) — só para não repetir a mesma lista de parâmetros nas duas
/// etapas de [PatrimonioRepositorySupabase._listarTudoNumerico] e no
/// caminho normal.
class _FiltrosComuns {
  const _FiltrosComuns({
    this.tipoId,
    this.status,
    this.setorId,
    this.localizacaoId,
    this.semLocalizacao = false,
    this.marca,
    this.modelo,
    this.responsavel,
    this.dataCadastroDe,
    this.dataCadastroAte,
    this.dataAquisicaoDe,
    this.dataAquisicaoAte,
  });

  final String? tipoId;
  final PatrimonioStatus? status;
  final String? setorId;
  final String? localizacaoId;
  final bool semLocalizacao;
  final String? marca;
  final String? modelo;
  final String? responsavel;
  final DateTime? dataCadastroDe;
  final DateTime? dataCadastroAte;
  final DateTime? dataAquisicaoDe;
  final DateTime? dataAquisicaoAte;
}

/// Início (00:00) do dia LOCAL de [data], convertido para o instante UTC
/// correspondente — para comparar corretamente com `data_cadastro`
/// (timestamptz) independente do fuso horário configurado no dispositivo.
DateTime _inicioDoDiaLocalEmUtc(DateTime data) =>
    DateTime(data.year, data.month, data.day).toUtc();

/// Início do dia LOCAL seguinte a [data] — usado como limite EXCLUSIVO do
/// intervalo (seção 5: `< início do dia seguinte`, nunca
/// `<= 23:59:59.999`, que poderia perder registros por causa da precisão
/// de subsegundo).
DateTime _inicioDoDiaSeguinteLocalEmUtc(DateTime data) =>
    DateTime(data.year, data.month, data.day + 1).toUtc();

/// `yyyy-MM-dd` de [data] — formato aceito por uma coluna `date` do
/// Postgres, sem nenhuma conversão de fuso (é só uma data, não um
/// instante).
String _formatarData(DateTime data) {
  final ano = data.year.toString().padLeft(4, '0');
  final mes = data.month.toString().padLeft(2, '0');
  final dia = data.day.toString().padLeft(2, '0');
  return '$ano-$mes-$dia';
}

class PatrimonioRepositorySupabase implements PatrimonioRepository {
  PatrimonioRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<Patrimonio?> buscarPorId(String id) async {
    try {
      final row = await _client
          .from('patrimonios')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Patrimonio.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
  }

  @override
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id) async {
    try {
      final row = await _client
          .from('patrimonios')
          // profiles só é embutido aqui (detalhe): a policy de profiles só
          // deixa ADMIN/GESTOR verem o nome de quem não é o próprio usuário
          // — para outros perfis o embed volta nulo, e a UI só omite
          // "Criado por" (ver PatrimonioDetalhe).
          .select('$_colunasComRelacionamentos, criado_por_profile:profiles(nome)')
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : PatrimonioDetalhe.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Patrimonio?> buscarPorNumeroPatrimonio(
    String numeroPatrimonio,
  ) async {
    final numero = normalizarNumeroPatrimonio(numeroPatrimonio);
    if (numero == null) return null;

    try {
      final row = await _client
          .from('patrimonios')
          .select()
          .eq('numero_patrimonio', numero)
          .maybeSingle();
      return row == null ? null : Patrimonio.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
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
    try {
      final termo = busca?.trim();
      final filtrosComuns = _FiltrosComuns(
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

      // PROMPT 9.1.1: modo "Tudo" com consulta só de dígitos tem uma
      // lógica própria em duas etapas (nunca mistura patrimônio com série
      // no mesmo resultado) — ver [_listarTudoNumerico].
      if (termo != null && termo.isNotEmpty && campoBusca == PatrimonioSearchField.tudo && _somenteDigitos(termo)) {
        return await _listarTudoNumerico(
          termo: termo,
          limit: limit,
          offset: offset,
          filtros: filtrosComuns,
        );
      }

      var query = _client.from('patrimonios').select(_colunasComRelacionamentos);

      if (termo != null && termo.isNotEmpty) {
        final resultado = await _aplicarFiltroBusca(query, campoBusca, termo);
        if (resultado == null) {
          // Ex.: modo "Localização" sem nenhuma localização cujo nome
          // corresponda ao termo — zero patrimônios podem casar, e ir ao
          // banco de qualquer forma só devolveria uma lista vazia do mesmo
          // jeito (seção 10: nunca uma query desnecessária).
          return const PatrimoniosResultado(itens: [], total: 0);
        }
        query = resultado;
      }
      query = _aplicarFiltrosComuns(query, filtrosComuns);
      return await _executarConsulta(query, limit: limit, offset: offset);
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
  }

  /// PROMPT 9.1.1: busca em duas etapas LÓGICAS para o modo "Tudo" quando a
  /// consulta é só dígitos — nunca uma única `OR` misturando patrimônio e
  /// série (o que fazia "2703522" devolver visualmente o patrimônio
  /// 2703532, só porque é o número de série dele).
  ///
  /// Etapa 1: `numero_patrimonio = termo` (exato). Se achar algo, é o
  /// resultado — [PatrimonioSearchField.numeroSerie] nunca entra em jogo.
  /// Etapa 2: só executa uma SEGUNDA consulta (nunca N+1: uma única query
  /// extra, e só quando a etapa 1 não achou nada) por `numero_serie =
  /// termo` (também exato) — o retorno vai em
  /// [PatrimoniosResultado.correspondenciasPorNumeroSerie], NUNCA em
  /// [PatrimoniosResultado.itens], para a UI nunca apresentar isso como se
  /// fosse o patrimônio pesquisado.
  Future<PatrimoniosResultado> _listarTudoNumerico({
    required String termo,
    required int limit,
    required int offset,
    required _FiltrosComuns filtros,
  }) async {
    final numero = normalizarNumeroPatrimonio(termo)!;

    var queryPatrimonio = _client
        .from('patrimonios')
        .select(_colunasComRelacionamentos)
        .eq('numero_patrimonio', numero);
    queryPatrimonio = _aplicarFiltrosComuns(queryPatrimonio, filtros);
    final resultadoPatrimonio = await _executarConsulta(queryPatrimonio, limit: limit, offset: offset);
    if (resultadoPatrimonio.total > 0) return resultadoPatrimonio;

    var querySerie = _client.from('patrimonios').select(_colunasComRelacionamentos).eq('numero_serie', termo);
    querySerie = _aplicarFiltrosComuns(querySerie, filtros);
    final resultadoSerie = await _executarConsulta(
      querySerie,
      limit: _limiteCorrespondenciaSerie,
      offset: 0,
    );

    return PatrimoniosResultado(
      itens: const [],
      total: 0,
      correspondenciasPorNumeroSerie: resultadoSerie.itens,
    );
  }

  /// Aplica tipo/status/setor/localização/marca/modelo/responsável/datas
  /// (PROMPT 9.2) — todos opcionais, combinados por AND. Usado pelo caminho
  /// normal e pelas duas etapas de [_listarTudoNumerico], sempre com a
  /// mesma lógica (nunca duplicada).
  PostgrestFilterBuilder<PostgrestList> _aplicarFiltrosComuns(
    PostgrestFilterBuilder<PostgrestList> query,
    _FiltrosComuns filtros,
  ) {
    var resultado = query;
    if (filtros.tipoId != null) {
      resultado = resultado.eq('tipo_id', filtros.tipoId!);
    }
    if (filtros.status != null) {
      resultado = resultado.eq('status', filtros.status!.value);
    }
    if (filtros.setorId != null) {
      resultado = resultado.eq('setor_atual_id', filtros.setorId!);
    }

    // Seção 2: por id exato, nunca por texto — e "Sem localização" é
    // mutuamente exclusivo com um id específico (a UI garante isso).
    if (filtros.semLocalizacao) {
      resultado = resultado.isFilter('localizacao_atual_id', null);
    } else if (filtros.localizacaoId != null) {
      resultado = resultado.eq('localizacao_atual_id', filtros.localizacaoId!);
    }

    final marca = filtros.marca?.trim();
    if (marca != null && marca.isNotEmpty) {
      resultado = resultado.ilike('marca', '%$marca%');
    }
    final modelo = filtros.modelo?.trim();
    if (modelo != null && modelo.isNotEmpty) {
      resultado = resultado.ilike('modelo', '%$modelo%');
    }
    final responsavel = filtros.responsavel?.trim();
    if (responsavel != null && responsavel.isNotEmpty) {
      resultado = resultado.ilike('responsavel_atual', '%$responsavel%');
    }

    // Seção 5: `data_cadastro` é timestamptz — usar `>= início do dia` e
    // `< início do dia seguinte` (nunca `23:59:59.999`), convertendo o dia
    // local do dispositivo para o instante UTC correspondente.
    if (filtros.dataCadastroDe != null) {
      resultado = resultado.gte('data_cadastro', _inicioDoDiaLocalEmUtc(filtros.dataCadastroDe!).toIso8601String());
    }
    if (filtros.dataCadastroAte != null) {
      resultado = resultado.lt(
        'data_cadastro',
        _inicioDoDiaSeguinteLocalEmUtc(filtros.dataCadastroAte!).toIso8601String(),
      );
    }

    // `data_aquisicao` é `date` (sem hora) — comparação direta, sem
    // conversão de fuso, ambos os limites inclusivos.
    if (filtros.dataAquisicaoDe != null) {
      resultado = resultado.gte('data_aquisicao', _formatarData(filtros.dataAquisicaoDe!));
    }
    if (filtros.dataAquisicaoAte != null) {
      resultado = resultado.lte('data_aquisicao', _formatarData(filtros.dataAquisicaoAte!));
    }

    return resultado;
  }

  /// Executa a consulta paginada e conta o total — registros mais recentes
  /// primeiro: é o que mais importa logo após o cadastro (validar o que
  /// acabou de ser criado) e não exige nenhuma convenção sobre número
  /// patrimonial (que é opcional e texto livre). `id` como critério de
  /// desempate (PROMPT 9.2, seção 11): `data_cadastro` sozinho não é único
  /// (a carga inicial da GETEC tem várias linhas com o mesmo instante), e
  /// sem uma ordem totalmente determinística um registro pode "pular" de
  /// página ou repetir entre duas páginas consecutivas.
  Future<PatrimoniosResultado> _executarConsulta(
    PostgrestFilterBuilder<PostgrestList> query, {
    required int limit,
    required int offset,
  }) async {
    final response = await query
        .order('data_cadastro', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1)
        .count(CountOption.exact);

    final itens = response.data.map(PatrimonioDetalhe.fromJson).toList();
    return PatrimoniosResultado(itens: itens, total: response.count);
  }

  /// Aplica o filtro de busca sobre [query], de acordo com [campo] (PROMPT
  /// 9.1) — nunca `ilike`/substring/similaridade para
  /// [PatrimonioSearchField.patrimonio], sempre correspondência EXATA.
  ///
  /// Retorna `null` quando já se sabe, sem consultar `patrimonios`, que
  /// NENHUM registro pode corresponder (hoje só o modo "Localização" sem
  /// nenhum nome correspondente) — o chamador então nem executa a consulta
  /// principal.
  ///
  /// Nunca chamado para o modo [PatrimonioSearchField.tudo] com consulta só
  /// de dígitos — esse caso é interceptado antes, em [listar], e vai para
  /// [_listarTudoNumerico].
  Future<PostgrestFilterBuilder<PostgrestList>?> _aplicarFiltroBusca(
    PostgrestFilterBuilder<PostgrestList> query,
    PatrimonioSearchField campo,
    String termo,
  ) async {
    switch (campo) {
      case PatrimonioSearchField.patrimonio:
        final numero = normalizarNumeroPatrimonio(termo)!;
        return query.eq('numero_patrimonio', numero);

      case PatrimonioSearchField.numeroSerie:
        // `.ilike()` é uma chamada direta do builder (não um `.or()`
        // montado à mão) — o padrão vai cru, sem `postgrestFilterValue`
        // (essa função só serve para escapar `,`/`(`/`)` dentro de uma
        // string `or=` construída manualmente; usá-la aqui enviaria aspas
        // literais como parte do padrão e nunca casaria com nada real).
        return query.ilike('numero_serie', '%$termo%');

      case PatrimonioSearchField.equipamentoDescricao:
        return query.ilike('descricao', '%$termo%');

      case PatrimonioSearchField.marcaModelo:
        // aqui sim: dentro de um `.or(...)` montado à mão, então precisa
        // do escape de `postgrestFilterValue`.
        final valor = postgrestFilterValue('%$termo%');
        return query.or('marca.ilike.$valor,modelo.ilike.$valor');

      case PatrimonioSearchField.responsavel:
        return query.ilike('responsavel_atual', '%$termo%');

      case PatrimonioSearchField.localizacao:
        final ids = await _idsLocalizacoesPorNome(termo);
        if (ids.isEmpty) return null;
        return query.inFilter('localizacao_atual_id', ids);

      case PatrimonioSearchField.tudo:
        // consulta só de dígitos nunca chega aqui (ver acima); só sobra o
        // ramo textual — mantém `numero_patrimonio` exato quando
        // aplicável, nunca substring nele.
        final valor = postgrestFilterValue('%$termo%');
        final numero = normalizarNumeroPatrimonio(termo)!;
        final ids = await _idsLocalizacoesPorNome(termo);
        final clausulas = [
          'numero_patrimonio.eq.${postgrestFilterValue(numero)}',
          'numero_serie.ilike.$valor',
          'marca.ilike.$valor',
          'modelo.ilike.$valor',
          'descricao.ilike.$valor',
          'responsavel_atual.ilike.$valor',
          if (ids.isNotEmpty) 'localizacao_atual_id.in.(${ids.join(',')})',
        ];
        return query.or(clausulas.join(','));
    }
  }

  /// Ids de `localizacoes` cujo `nome` contém [termo] (case-insensitive) —
  /// uma única consulta, nunca uma por patrimônio (seção 10: proibido
  /// N+1). Usado tanto pelo modo dedicado "Localização" quanto pelo modo
  /// "Tudo" textual. Chamada direta de `.ilike()` — padrão cru, sem
  /// `postgrestFilterValue` (ver comentário em [_aplicarFiltroBusca]).
  Future<List<String>> _idsLocalizacoesPorNome(String termo) async {
    final rows = await _client.from('localizacoes').select('id').ilike('nome', '%$termo%');
    return rows.map((row) => row['id'] as String).toList();
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
    try {
      final row = await _client.rpc(
        'cadastrar_patrimonio',
        params: {
          'p_tipo_id': tipoId,
          'p_destino_id': destinoId,
          'p_numero_patrimonio': numeroPatrimonio,
          'p_numero_serie': numeroSerie,
          'p_marca': _semEspacosOuNulo(marca),
          'p_modelo': _semEspacosOuNulo(modelo),
          'p_descricao': _semEspacosOuNulo(descricao),
          'p_observacao': _semEspacosOuNulo(observacao),
          if (dataAquisicao != null)
            'p_data_aquisicao': dataAquisicao.toIso8601String().substring(
              0,
              10,
            ),
          'p_origem_id': origemId,
          'p_responsavel_origem': responsavelOrigem,
          'p_responsavel_destino': responsavelDestino,
          'p_motivo': _semEspacosOuNulo(motivo),
          'p_observacao_movimentacao': _semEspacosOuNulo(
            observacaoMovimentacao,
          ),
          if (dataMovimentacao != null)
            'p_data_movimentacao': dataMovimentacao.toIso8601String(),
          'p_localizacao_destino_id': localizacaoDestinoId,
          'p_localizacao_origem_id': localizacaoOrigemId,
        },
      );
      return Patrimonio.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
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
    try {
      final row = await _client
          .from('patrimonios')
          .update({
            'numero_patrimonio': numeroPatrimonio,
            'numero_serie': numeroSerie,
            'tipo_id': tipoId,
            'marca': _semEspacosOuNulo(marca),
            'modelo': _semEspacosOuNulo(modelo),
            'descricao': _semEspacosOuNulo(descricao),
            'observacao': _semEspacosOuNulo(observacao),
            'data_aquisicao': dataAquisicao?.toIso8601String().substring(
              0,
              10,
            ),
          })
          .eq('id', id)
          .select()
          .single();
      return Patrimonio.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
  }

  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros) async {
    if (numeros.isEmpty) return [];
    try {
      final resultado = <PatrimonioDetalhe>[];
      // Consulta em lotes: evita tanto o N+1 (uma requisição por número)
      // quanto uma URL excessivamente longa quando a planilha tem milhares
      // de linhas.
      for (final lote in _emLotes(numeros, _tamanhoLoteConsulta)) {
        final rows = await _client
            .from('patrimonios')
            .select(_colunasComRelacionamentos)
            .inFilter('numero_patrimonio', lote);
        resultado.addAll(rows.map(PatrimonioDetalhe.fromJson));
      }
      return resultado;
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) async {
    if (numerosSerie.isEmpty) return {};
    try {
      final resultado = <String>{};
      for (final lote in _emLotes(numerosSerie, _tamanhoLoteConsulta)) {
        final rows = await _client
            .from('patrimonios')
            .select('numero_serie')
            .inFilter('numero_serie', lote);
        resultado.addAll(rows.map((row) => row['numero_serie'] as String));
      }
      return resultado;
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
  }
}

const _tamanhoLoteConsulta = 200;

Iterable<List<String>> _emLotes(List<String> valores, int tamanho) sync* {
  for (var i = 0; i < valores.length; i += tamanho) {
    yield valores.sublist(i, i + tamanho > valores.length ? valores.length : i + tamanho);
  }
}

String? _semEspacosOuNulo(String? valor) {
  final normalizado = valor?.trim();
  return (normalizado == null || normalizado.isEmpty) ? null : normalizado;
}

final patrimonioRepositoryProvider = Provider<PatrimonioRepository>((ref) {
  return PatrimonioRepositorySupabase(Supabase.instance.client);
});
