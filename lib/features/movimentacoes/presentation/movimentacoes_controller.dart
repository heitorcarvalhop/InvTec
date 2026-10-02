import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/ordenacao_direcao.dart';
import '../data/movimentacao_repository_supabase.dart';
import '../domain/movimentacao.dart';
import '../domain/movimentacao_ordenacao.dart';
import '../domain/movimentacoes_resultado.dart';
import 'movimentacoes_filtro.dart';

final movimentacoesControllerProvider =
    AsyncNotifierProvider<MovimentacoesController, MovimentacoesListState>(
      MovimentacoesController.new,
    );

class MovimentacoesListState {
  const MovimentacoesListState({required this.filtro, required this.resultado});

  final MovimentacoesFiltro filtro;
  final MovimentacoesResultado resultado;

  int get totalPaginas => resultado.total == 0 ? 1 : ((resultado.total - 1) ~/ filtro.tamanhoPagina) + 1;
}

/// Lista geral de movimentações: busca com debounce, filtros
/// (tipo/setor/período) e paginação — todos resolvidos no servidor via
/// [MovimentacaoRepository.listar]. Somente leitura: nenhum método de
/// escrita aqui (registrar movimentação continua exclusivo da tela de
/// detalhe do patrimônio).
class MovimentacoesController extends AsyncNotifier<MovimentacoesListState> {
  Timer? _debounceBusca;
  MovimentacoesFiltro _filtro = const MovimentacoesFiltro();

  @override
  Future<MovimentacoesListState> build() async {
    ref.onDispose(() => _debounceBusca?.cancel());
    final repository = ref.watch(movimentacaoRepositoryProvider);
    final resultado = await repository.listar(
      limit: _filtro.tamanhoPagina,
      offset: _filtro.pagina * _filtro.tamanhoPagina,
      busca: _filtro.busca,
      tipo: _filtro.tipo,
      setorId: _filtro.setorId,
      periodoDe: _filtro.periodoDe,
      periodoAte: _filtro.periodoAte,
      ordenarPor: _filtro.ordenarPor,
      ordenacaoDirecao: _filtro.ordenacaoDirecao,
    );
    return MovimentacoesListState(filtro: _filtro, resultado: resultado);
  }

  /// Mesmo ciclo de clique de Patrimônios — ver
  /// [PatrimoniosController.ordenarPor] — para a UX nunca divergir entre as
  /// duas telas.
  void ordenarPor(MovimentacaoOrdenacaoCampo campo) {
    final (novoCampo, novaDirecao) = proximoEstadoDeOrdenacao(
      campoAtual: _filtro.ordenarPor,
      direcaoAtual: _filtro.ordenarPor == null ? null : _filtro.ordenacaoDirecao,
      campoClicado: campo,
    );
    _filtro = _filtro.copyWith(
      ordenarPor: novoCampo,
      ordenacaoDirecao: novaDirecao ?? OrdenacaoDirecao.asc,
      pagina: 0,
    );
    ref.invalidateSelf();
  }

  /// Busca com debounce (300ms, mesmo valor de Patrimônios) — sempre volta
  /// para a primeira página. Uma resposta antiga que chegue depois de uma
  /// mais nova nunca sobrescreve o estado (garantia do próprio
  /// `AsyncNotifier`/`invalidateSelf()`).
  void buscar(String texto) {
    _debounceBusca?.cancel();
    _debounceBusca = Timer(const Duration(milliseconds: 300), () {
      _filtro = _filtro.copyWith(busca: texto.trim(), pagina: 0);
      ref.invalidateSelf();
    });
  }

  void filtrarPorTipo(MovimentacaoTipo? tipo) {
    _filtro = _filtro.copyWith(tipo: tipo, pagina: 0);
    ref.invalidateSelf();
  }

  void filtrarPorSetor(String? setorId) {
    _filtro = _filtro.copyWith(setorId: setorId, pagina: 0);
    ref.invalidateSelf();
  }

  void definirPeriodo(DateTime? de, DateTime? ate) {
    _filtro = _filtro.copyWith(periodoDe: de, periodoAte: ate, pagina: 0);
    ref.invalidateSelf();
  }

  void definirTamanhoPagina(int tamanho) {
    _filtro = _filtro.copyWith(tamanhoPagina: tamanho, pagina: 0);
    ref.invalidateSelf();
  }

  void limparFiltros() {
    _debounceBusca?.cancel();
    _filtro = const MovimentacoesFiltro();
    ref.invalidateSelf();
  }

  void irParaPagina(int pagina) {
    _filtro = _filtro.copyWith(pagina: pagina);
    ref.invalidateSelf();
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}
