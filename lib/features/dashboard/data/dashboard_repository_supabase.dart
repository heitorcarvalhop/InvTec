import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/categoria_contagem.dart';
import '../domain/dashboard_distribuicoes.dart';
import '../domain/dashboard_repository.dart';
import '../domain/movimentacao_resumo.dart';

/// Quantas categorias mostrar em "Patrimônios por tipo" e "Locais com mais
/// patrimônios" — os setores (hoje poucos) aparecem todos, sem corte.
const _topTipos = 8;
const _topLocalizacoes = 5;
const _tamanhoPagina = 1000;

class DashboardRepositorySupabase implements DashboardRepository {
  DashboardRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<int> contarPatrimonios() async {
    try {
      final response = await _client
          .from('patrimonios')
          .count(CountOption.exact);
      return response;
    } on PostgrestException catch (e) {
      throw AppException('Falha ao contar patrimônios', cause: e);
    }
  }

  @override
  Future<int> contarSetoresAtivos() async {
    try {
      final response = await _client
          .from('setores')
          .count(CountOption.exact)
          .eq('ativo', true);
      return response;
    } on PostgrestException catch (e) {
      throw AppException('Falha ao contar setores', cause: e);
    }
  }

  @override
  Future<int> contarLocalizacoesAtivas() async {
    try {
      final response = await _client
          .from('localizacoes')
          .count(CountOption.exact)
          .eq('ativo', true);
      return response;
    } on PostgrestException catch (e) {
      throw AppException('Falha ao contar localizações', cause: e);
    }
  }

  @override
  Future<int> contarTiposAtivos() async {
    try {
      final response = await _client
          .from('tipos_patrimonio')
          .count(CountOption.exact)
          .eq('ativo', true);
      return response;
    } on PostgrestException catch (e) {
      throw AppException('Falha ao contar tipos de patrimônio', cause: e);
    }
  }

  @override
  Future<int> contarMovimentacoesDesde(DateTime desde) async {
    try {
      final response = await _client
          .from('movimentacoes')
          .count(CountOption.exact)
          .gte('data_movimentacao', desde.toUtc().toIso8601String());
      return response;
    } on PostgrestException catch (e) {
      throw AppException('Falha ao contar movimentações recentes', cause: e);
    }
  }

  @override
  Future<DashboardDistribuicoes> carregarDistribuicoes() async {
    try {
      // Só as colunas de agrupamento + o nome embutido de cada categoria
      // (nunca `select('*')`). O Postgrest não expõe `GROUP BY` sem uma
      // view/RPC dedicada, então a agregação é feita aqui, em memória.
      //
      // IMPORTANTE: o Supabase corta qualquer resposta em `max_rows`
      // (1000 por padrão). Sem paginar, com milhares de patrimônios só as
      // primeiras 1000 linhas (sem ordem definida) eram contadas e os
      // setores/percentuais saíam errados. Por isso lemos em páginas, com
      // ordem estável por `id`, até esgotar a tabela.
      final rows = <Map<String, dynamic>>[];
      var inicio = 0;
      while (true) {
        final pagina = await _client
            .from('patrimonios')
            .select(
              'setor_atual_id, setores(nome, sigla), '
              'tipo_id, tipos_patrimonio(nome), '
              'localizacao_atual_id, localizacoes(nome)',
            )
            .order('id')
            .range(inicio, inicio + _tamanhoPagina - 1);
        rows.addAll(pagina);
        // Página curta = fim da tabela.
        if (pagina.length < _tamanhoPagina) break;
        inicio += _tamanhoPagina;
      }

      final porSetor = <String, _Contagem>{};
      final porTipo = <String, _Contagem>{};
      final porLocalizacao = <String, _Contagem>{};

      for (final row in rows) {
        final setorId = row['setor_atual_id'] as String?;
        final setor = row['setores'] as Map<String, dynamic>?;
        if (setorId != null && setor != null) {
          final nome = (setor['sigla'] as String?) ?? (setor['nome'] as String);
          porSetor.update(
            setorId,
            (c) => c.incrementado(),
            ifAbsent: () => _Contagem(nome: nome, quantidade: 1),
          );
        }

        final tipoId = row['tipo_id'] as String?;
        final tipo = row['tipos_patrimonio'] as Map<String, dynamic>?;
        if (tipoId != null && tipo != null) {
          porTipo.update(
            tipoId,
            (c) => c.incrementado(),
            ifAbsent: () =>
                _Contagem(nome: tipo['nome'] as String, quantidade: 1),
          );
        }

        final localizacaoId = row['localizacao_atual_id'] as String?;
        final localizacao = row['localizacoes'] as Map<String, dynamic>?;
        if (localizacaoId != null && localizacao != null) {
          porLocalizacao.update(
            localizacaoId,
            (c) => c.incrementado(),
            ifAbsent: () =>
                _Contagem(nome: localizacao['nome'] as String, quantidade: 1),
          );
        }
      }

      final totalConsiderado = porSetor.values.fold(
        0,
        (soma, c) => soma + c.quantidade,
      );

      return DashboardDistribuicoes(
        porSetor: _ordenado(porSetor),
        porTipo: _ordenado(porTipo).take(_topTipos).toList(),
        topLocalizacoes: _ordenado(
          porLocalizacao,
        ).take(_topLocalizacoes).toList(),
        totalConsiderado: totalConsiderado,
      );
    } on PostgrestException catch (e) {
      throw AppException(
        'Falha ao carregar a distribuição de patrimônios',
        cause: e,
      );
    }
  }

  @override
  Future<List<MovimentacaoResumo>> listarMovimentacoesRecentes({
    int limit = 8,
  }) async {
    try {
      final rows = await _client
          .from('movimentacoes')
          .select(
            'id, tipo, data_movimentacao, '
            'patrimonios(numero_patrimonio, descricao), '
            'origem:setores!origem_id(nome, sigla), '
            'destino:setores!destino_id(nome, sigla), '
            'autor:profiles!realizado_por(nome)',
          )
          .order('data_movimentacao', ascending: false)
          .order('criado_em', ascending: false)
          .limit(limit);

      return rows.map(MovimentacaoResumo.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException('Falha ao carregar movimentações recentes', cause: e);
    }
  }
}

class _Contagem {
  const _Contagem({required this.nome, required this.quantidade});

  final String nome;
  final int quantidade;

  _Contagem incrementado() => _Contagem(nome: nome, quantidade: quantidade + 1);
}

List<CategoriaContagem> _ordenado(Map<String, _Contagem> contagens) {
  final itens =
      contagens.entries
          .map(
            (e) => CategoriaContagem(
              id: e.key,
              nome: e.value.nome,
              quantidade: e.value.quantidade,
            ),
          )
          .toList()
        ..sort((a, b) => b.quantidade.compareTo(a.quantidade));
  return itens;
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositorySupabase(Supabase.instance.client);
});
