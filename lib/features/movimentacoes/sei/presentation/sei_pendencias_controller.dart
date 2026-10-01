import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/movimentacao.dart';
import '../data/documentos_sei_repository_supabase.dart';
import '../domain/documentos_sei_resultado.dart';
import '../domain/sei_item_pendencia_status.dart';
import 'sei_pendencias_filtro.dart';

final seiPendenciasControllerProvider = AsyncNotifierProvider<SeiPendenciasController, SeiPendenciasListState>(
  SeiPendenciasController.new,
);

class SeiPendenciasListState {
  const SeiPendenciasListState({required this.filtro, required this.resultado});

  final SeiPendenciasFiltro filtro;
  final DocumentosSeiResultado resultado;

  int get totalPaginas => resultado.total == 0 ? 1 : ((resultado.total - 1) ~/ filtro.tamanhoPagina) + 1;
}

/// Lista de Documentos SEI pendentes (PROMPT 11.3, seção 4) — somente
/// leitura: nenhum método aqui cria, edita, cancela ou conclui nada (essas
/// ações vivem em `DocumentosSeiRepository`, chamadas a partir da tela de
/// detalhe). Mesmo padrão de `MovimentacoesController`: busca com debounce
/// (aqui, por número de documento/processo/patrimônio) e paginação
/// resolvidas no servidor.
class SeiPendenciasController extends AsyncNotifier<SeiPendenciasListState> {
  Timer? _debounce;
  SeiPendenciasFiltro _filtro = const SeiPendenciasFiltro();

  @override
  Future<SeiPendenciasListState> build() async {
    ref.onDispose(() => _debounce?.cancel());
    final repositorio = ref.watch(documentosSeiRepositoryProvider);
    final resultado = await repositorio.listar(
      limit: _filtro.tamanhoPagina,
      offset: _filtro.pagina * _filtro.tamanhoPagina,
      tipo: _filtro.tipo,
      situacaoContemStatus: _filtro.situacaoContemStatus,
      numeroDocumentoSei: _filtro.numeroDocumentoSei,
      numeroProcesso: _filtro.numeroProcesso,
      numeroPatrimonio: _filtro.numeroPatrimonio,
    );
    return SeiPendenciasListState(filtro: _filtro, resultado: resultado);
  }

  void buscarPorDocumento(String texto) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _filtro = _filtro.copyWith(numeroDocumentoSei: () => texto.trim(), pagina: 0);
      ref.invalidateSelf();
    });
  }

  void filtrarPorTipo(MovimentacaoTipo? tipo) {
    _filtro = _filtro.copyWith(tipo: () => tipo, pagina: 0);
    ref.invalidateSelf();
  }

  void filtrarPorSituacao(SeiItemPendenciaStatus? status) {
    _filtro = _filtro.copyWith(situacaoContemStatus: () => status, pagina: 0);
    ref.invalidateSelf();
  }

  void limparFiltros() {
    _debounce?.cancel();
    _filtro = const SeiPendenciasFiltro();
    ref.invalidateSelf();
  }

  void irParaPagina(int pagina) {
    _filtro = _filtro.copyWith(pagina: pagina);
    ref.invalidateSelf();
  }

  void definirTamanhoPagina(int tamanho) {
    _filtro = _filtro.copyWith(tamanhoPagina: tamanho, pagina: 0);
    ref.invalidateSelf();
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}
