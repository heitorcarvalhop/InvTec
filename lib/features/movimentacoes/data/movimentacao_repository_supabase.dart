import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/postgrest_filter.dart';
import '../../../core/utils/text_normalization.dart';
import '../domain/movimentacao.dart';
import '../domain/movimentacao_historico_item.dart';
import '../domain/movimentacao_listagem_item.dart';
import '../domain/movimentacao_repository.dart';
import '../domain/movimentacoes_resultado.dart';
import 'movimentacao_error_mapper.dart';

/// Colunas + relacionamentos exibidos pela listagem geral (PROMPT 10.1) —
/// uma única consulta via embed do Postgrest, nunca uma por linha.
/// `setores`/`localizacoes` têm duas FKs cada (origem/destino), então cada
/// embed precisa do alias `tabela!coluna(...)` para desambiguar.
const _colunasListagem =
    'id, tipo, data_movimentacao, responsavel_origem, responsavel_destino, motivo, observacao, '
    'numero_documento, numero_chamado, patrimonio_id, origem_id, destino_id, '
    'patrimonios(numero_patrimonio, tipos_patrimonio(nome)), '
    'setor_origem:setores!origem_id(nome), '
    'setor_destino:setores!destino_id(nome), '
    'localizacao_origem:localizacoes!localizacao_origem_id(nome), '
    'localizacao_destino:localizacoes!localizacao_destino_id(nome), '
    'autor:profiles!realizado_por(nome)';

/// Início (00:00) do dia LOCAL de [data], convertido para o instante UTC
/// correspondente — mesmo critério de `PatrimonioRepositorySupabase` para
/// comparar corretamente com uma coluna `timestamptz`.
DateTime _inicioDoDiaLocalEmUtc(DateTime data) =>
    DateTime(data.year, data.month, data.day).toUtc();

/// Início do dia LOCAL seguinte a [data] — limite EXCLUSIVO superior do
/// intervalo (nunca `23:59:59.999`, que pode perder registros por
/// precisão de subsegundo).
DateTime _inicioDoDiaSeguinteLocalEmUtc(DateTime data) =>
    DateTime(data.year, data.month, data.day + 1).toUtc();

class MovimentacaoRepositorySupabase implements MovimentacaoRepository {
  MovimentacaoRepositorySupabase(this._client);

  final SupabaseClient _client;

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
    try {
      var query = _client.from('movimentacoes').select(_colunasListagem);

      final termo = busca?.trim();
      if (termo != null && termo.isNotEmpty) {
        final valor = postgrestFilterValue('%$termo%');
        // Uma única consulta extra para resolver quais patrimônios têm o
        // número buscado (nunca uma por linha da página) — mesmo padrão de
        // `PatrimonioRepositorySupabase._idsLocalizacoesPorNome`.
        final idsPatrimonio = await _idsPatrimoniosPorNumero(termo);
        final clausulas = [
          'responsavel_origem.ilike.$valor',
          'responsavel_destino.ilike.$valor',
          'numero_documento.ilike.$valor',
          'numero_chamado.ilike.$valor',
          if (idsPatrimonio.isNotEmpty) 'patrimonio_id.in.(${idsPatrimonio.join(',')})',
        ];
        query = query.or(clausulas.join(','));
      }

      if (tipo != null) {
        query = query.eq('tipo', tipo.value);
      }

      // "Setor" sem distinguir lado: casa se o setor foi origem OU destino
      // da movimentação (PROMPT 10.1).
      if (setorId != null) {
        query = query.or('origem_id.eq.$setorId,destino_id.eq.$setorId');
      }

      if (periodoDe != null) {
        query = query.gte('data_movimentacao', _inicioDoDiaLocalEmUtc(periodoDe).toIso8601String());
      }
      if (periodoAte != null) {
        query = query.lt('data_movimentacao', _inicioDoDiaSeguinteLocalEmUtc(periodoAte).toIso8601String());
      }

      final response = await query
          .order('data_movimentacao', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + limit - 1)
          .count(CountOption.exact);

      final itens = response.data.map(MovimentacaoListagemItem.fromJson).toList();
      return MovimentacoesResultado(itens: itens, total: response.count);
    } on PostgrestException catch (e) {
      throw AppException('Falha ao listar movimentações', cause: e);
    }
  }

  /// Ids de `patrimonios` cujo `numero_patrimonio` contém [termo]
  /// (case-insensitive) — uma única consulta, nunca uma por linha da
  /// página.
  Future<List<String>> _idsPatrimoniosPorNumero(String termo) async {
    final rows = await _client.from('patrimonios').select('id').ilike('numero_patrimonio', '%$termo%');
    return rows.map((row) => row['id'] as String).toList();
  }

  @override
  Future<List<Movimentacao>> listarPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client
          .from('movimentacoes')
          .select()
          .eq('patrimonio_id', patrimonioId)
          .order('data_movimentacao', ascending: false)
          .order('criado_em', ascending: false)
          .range(offset, offset + limit - 1);

      return rows.map(Movimentacao.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Falha ao listar movimentações do patrimônio',
        cause: e,
      );
    }
  }

  @override
  Future<List<MovimentacaoHistoricoItem>> listarHistoricoPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client
          .from('movimentacoes')
          .select(
            'id, tipo, data_movimentacao, responsavel_origem, responsavel_destino, motivo, observacao, '
            'setor_origem:setores!origem_id(nome), '
            'setor_destino:setores!destino_id(nome), '
            'localizacao_origem:localizacoes!localizacao_origem_id(nome), '
            'localizacao_destino:localizacoes!localizacao_destino_id(nome)',
          )
          .eq('patrimonio_id', patrimonioId)
          .order('data_movimentacao', ascending: false)
          .order('criado_em', ascending: false)
          .range(offset, offset + limit - 1);

      return rows.map(MovimentacaoHistoricoItem.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Falha ao carregar o histórico de movimentações do patrimônio',
        cause: e,
      );
    }
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
    try {
      final row = await _client.rpc(
        'registrar_movimentacao',
        params: buildRegistrarMovimentacaoParams(
          patrimonioId: patrimonioId,
          tipo: tipo,
          destinoId: destinoId,
          localizacaoDestinoId: localizacaoDestinoId,
          limparLocalizacao: limparLocalizacao,
          responsavelDestino: responsavelDestino,
          motivo: motivo,
          observacao: observacao,
          numeroDocumento: numeroDocumento,
          numeroChamado: numeroChamado,
          dataMovimentacao: dataMovimentacao,
        ),
      );
      return Movimentacao.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw AppException(mapMovimentacaoErrorMessage(e), cause: e);
    }
  }
}

/// Monta o mapa de parâmetros enviado a `registrar_movimentacao` — função
/// pura (sem `SupabaseClient`, sem I/O), para poder testar a normalização
/// isolada de produção. PROMPT 10.2.3: os cinco campos textuais opcionais
/// nunca são enviados como `""` — um `TextEditingController` vazio sempre
/// produz string vazia, nunca `null`, então sem isso o banco gravava `""`
/// em vez de `NULL` (confirmado no primeiro registro real:
/// numero_documento/numero_chamado ficaram `""`). A RPC só normaliza
/// `p_responsavel_destino` sozinha (`normalize_text` no corpo da função);
/// motivo/observacao/numero_documento/numero_chamado vão direto para o
/// INSERT sem tratamento — por isso normalizamos os cinco aqui, no único
/// lugar por onde toda chamada real passa. `destinoId`/`localizacaoDestinoId`
/// nunca passam por aqui: já são ids resolvidos pela UI (nunca texto livre
/// digitado), e `null` já é a representação correta de "não informado" para
/// os dois.
Map<String, Object?> buildRegistrarMovimentacaoParams({
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
}) {
  return {
    'p_patrimonio_id': patrimonioId,
    'p_tipo': tipo.value,
    'p_destino_id': destinoId,
    'p_responsavel_destino': nullIfBlank(responsavelDestino),
    'p_motivo': nullIfBlank(motivo),
    'p_observacao': nullIfBlank(observacao),
    'p_numero_documento': nullIfBlank(numeroDocumento),
    'p_numero_chamado': nullIfBlank(numeroChamado),
    if (dataMovimentacao != null) 'p_data_movimentacao': dataMovimentacao.toIso8601String(),
    'p_localizacao_destino_id': localizacaoDestinoId,
    'p_limpar_localizacao': limparLocalizacao,
  };
}

final movimentacaoRepositoryProvider = Provider<MovimentacaoRepository>((
  ref,
) {
  return MovimentacaoRepositorySupabase(Supabase.instance.client);
});
