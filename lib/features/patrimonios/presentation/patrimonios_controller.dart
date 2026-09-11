import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/presentation/dashboard_providers.dart';
import '../data/patrimonio_repository_supabase.dart';
import '../domain/patrimonio.dart';
import '../domain/patrimonios_resultado.dart';
import 'patrimonios_filtro.dart';

/// Tamanho de página da listagem — patrimônios podem chegar a milhares,
/// nunca carregamos tudo de uma vez.
const patrimoniosPageSize = 25;

final patrimoniosControllerProvider =
    AsyncNotifierProvider<PatrimoniosController, PatrimoniosListState>(
      PatrimoniosController.new,
    );

class PatrimoniosListState {
  const PatrimoniosListState({required this.filtro, required this.resultado});

  final PatrimoniosFiltro filtro;
  final PatrimoniosResultado resultado;

  int get totalPaginas =>
      resultado.total == 0
          ? 1
          : ((resultado.total - 1) ~/ patrimoniosPageSize) + 1;
}

/// Lista de patrimônios da tela de gestão: busca com debounce, filtros
/// (tipo/status/setor) e paginação — todos resolvidos no servidor (ver
/// [PatrimonioRepositorySupabase.listar]). Também concentra as ações de
/// escrita (cadastrar/atualizar), para recarregar a lista — e o dashboard,
/// quando um novo patrimônio é cadastrado — automaticamente após sucesso.
class PatrimoniosController extends AsyncNotifier<PatrimoniosListState> {
  Timer? _debounce;
  PatrimoniosFiltro _filtro = const PatrimoniosFiltro();

  @override
  Future<PatrimoniosListState> build() async {
    ref.onDispose(() => _debounce?.cancel());
    final repository = ref.watch(patrimonioRepositoryProvider);
    final resultado = await repository.listar(
      limit: patrimoniosPageSize,
      offset: _filtro.pagina * patrimoniosPageSize,
      busca: _filtro.busca,
      tipoId: _filtro.tipoId,
      status: _filtro.status,
      setorId: _filtro.setorId,
    );
    return PatrimoniosListState(filtro: _filtro, resultado: resultado);
  }

  /// Busca/filtro sempre volta para a primeira página.
  void buscar(String texto) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _filtro = _filtro.copyWith(busca: texto.trim(), pagina: 0);
      ref.invalidateSelf();
    });
  }

  void filtrarPorTipo(String? tipoId) {
    _debounce?.cancel();
    _filtro = _filtro.copyWith(tipoId: tipoId, pagina: 0);
    ref.invalidateSelf();
  }

  void filtrarPorStatus(PatrimonioStatus? status) {
    _debounce?.cancel();
    _filtro = _filtro.copyWith(status: status, pagina: 0);
    ref.invalidateSelf();
  }

  void filtrarPorSetor(String? setorId) {
    _debounce?.cancel();
    _filtro = _filtro.copyWith(setorId: setorId, pagina: 0);
    ref.invalidateSelf();
  }

  void limparFiltros() {
    _debounce?.cancel();
    _filtro = const PatrimoniosFiltro();
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
    final patrimonio = await ref
        .read(patrimonioRepositoryProvider)
        .cadastrar(
          tipoId: tipoId,
          destinoId: destinoId,
          numeroPatrimonio: numeroPatrimonio,
          numeroSerie: numeroSerie,
          marca: marca,
          modelo: modelo,
          descricao: descricao,
          observacao: observacao,
          dataAquisicao: dataAquisicao,
          origemId: origemId,
          responsavelOrigem: responsavelOrigem,
          responsavelDestino: responsavelDestino,
          motivo: motivo,
          observacaoMovimentacao: observacaoMovimentacao,
          dataMovimentacao: dataMovimentacao,
        );
    ref.invalidateSelf();
    ref.invalidate(dashboardDataProvider);
    return patrimonio;
  }

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
    final patrimonio = await ref
        .read(patrimonioRepositoryProvider)
        .atualizar(
          id: id,
          numeroPatrimonio: numeroPatrimonio,
          numeroSerie: numeroSerie,
          tipoId: tipoId,
          marca: marca,
          modelo: modelo,
          descricao: descricao,
          observacao: observacao,
          dataAquisicao: dataAquisicao,
        );
    ref.invalidateSelf();
    return patrimonio;
  }
}
