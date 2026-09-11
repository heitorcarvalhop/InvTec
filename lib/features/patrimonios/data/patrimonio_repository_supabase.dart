import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/postgrest_filter.dart';
import '../domain/patrimonio.dart';
import '../domain/patrimonio_detalhe.dart';
import '../domain/patrimonio_repository.dart';
import '../domain/patrimonios_resultado.dart';
import 'patrimonio_error_mapper.dart';

/// Colunas de `patrimonios` + os relacionamentos exibidos na interface, sem
/// consulta adicional por linha (uma única viagem ao Postgrest via embed).
/// Só há uma FK de `patrimonios` para `tipos_patrimonio`/`setores`, então
/// não há ambiguidade a desambiguar (diferente de `movimentacoes`, que tem
/// duas FKs para `setores`).
const _colunasComRelacionamentos =
    '*, tipos_patrimonio(nome), setores(nome)';

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
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
  }) async {
    try {
      var query = _client.from('patrimonios').select(_colunasComRelacionamentos);

      final termo = busca?.trim();
      if (termo != null && termo.isNotEmpty) {
        final valor = postgrestFilterValue('%$termo%');
        query = query.or(
          'numero_patrimonio.ilike.$valor,'
          'numero_serie.ilike.$valor,'
          'marca.ilike.$valor,'
          'modelo.ilike.$valor,'
          'descricao.ilike.$valor',
        );
      }
      if (tipoId != null) {
        query = query.eq('tipo_id', tipoId);
      }
      if (status != null) {
        query = query.eq('status', status.value);
      }
      if (setorId != null) {
        query = query.eq('setor_atual_id', setorId);
      }

      // registros mais recentes primeiro: é o que mais importa logo após o
      // cadastro (validar o que acabou de ser criado) e não exige nenhuma
      // convenção sobre número patrimonial (que é opcional e texto livre).
      final response = await query
          .order('data_cadastro', ascending: false)
          .range(offset, offset + limit - 1)
          .count(CountOption.exact);

      final itens = response.data.map(PatrimonioDetalhe.fromJson).toList();
      return PatrimoniosResultado(itens: itens, total: response.count);
    } on PostgrestException catch (e) {
      throw AppException(mapPatrimonioErrorMessage(e), cause: e);
    }
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
