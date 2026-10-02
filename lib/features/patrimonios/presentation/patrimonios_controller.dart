import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/ordenacao_direcao.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../data/patrimonio_repository_supabase.dart';
import '../domain/patrimonio.dart';
import '../domain/patrimonio_ordenacao.dart';
import '../domain/patrimonio_search_field.dart';
import '../domain/patrimonios_resultado.dart';
import 'patrimonios_filtro.dart';

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
          : ((resultado.total - 1) ~/ filtro.tamanhoPagina) + 1;
}

/// Lista de patrimônios da tela de gestão: busca com debounce, filtros
/// (tipo/status/setor) e paginação — todos resolvidos no servidor (ver
/// [PatrimonioRepositorySupabase.listar]). Também concentra as ações de
/// escrita (cadastrar/atualizar), para recarregar a lista — e o dashboard,
/// quando um novo patrimônio é cadastrado — automaticamente após sucesso.
class PatrimoniosController extends AsyncNotifier<PatrimoniosListState> {
  /// Um timer por campo debounced (busca principal + marca/modelo/
  /// responsável) — nunca compartilhados: trocar um filtro IMEDIATO (tipo/
  /// status/setor/localização/datas/tamanho de página) nunca cancela uma
  /// digitação pendente em outro campo debounced, senão o texto digitado
  /// seria silenciosamente perdido.
  Timer? _debounceBusca;
  Timer? _debounceMarca;
  Timer? _debounceModelo;
  Timer? _debounceResponsavel;
  PatrimoniosFiltro _filtro = const PatrimoniosFiltro();

  @override
  Future<PatrimoniosListState> build() async {
    ref.onDispose(() {
      _debounceBusca?.cancel();
      _debounceMarca?.cancel();
      _debounceModelo?.cancel();
      _debounceResponsavel?.cancel();
    });
    final repository = ref.watch(patrimonioRepositoryProvider);
    final resultado = await repository.listar(
      limit: _filtro.tamanhoPagina,
      offset: _filtro.pagina * _filtro.tamanhoPagina,
      busca: _filtro.busca,
      campoBusca: _filtro.campoBusca,
      tipoId: _filtro.tipoId,
      status: _filtro.status,
      setorId: _filtro.setorId,
      localizacaoId: _filtro.localizacaoId,
      semLocalizacao: _filtro.semLocalizacao,
      marca: _filtro.marca,
      modelo: _filtro.modelo,
      responsavel: _filtro.responsavel,
      dataCadastroDe: _filtro.dataCadastroDe,
      dataCadastroAte: _filtro.dataCadastroAte,
      dataAquisicaoDe: _filtro.dataAquisicaoDe,
      dataAquisicaoAte: _filtro.dataAquisicaoAte,
      ordenarPor: _filtro.ordenarPor,
      ordenacaoDirecao: _filtro.ordenacaoDirecao,
    );
    return PatrimoniosListState(filtro: _filtro, resultado: resultado);
  }

  /// Busca com debounce de 300ms (evita uma consulta remota a cada tecla) —
  /// sempre volta para a primeira página. `invalidateSelf()` só é chamado
  /// depois do debounce expirar; se o texto mudar antes disso, o timer
  /// anterior é cancelado. Se duas consultas ainda assim ficarem em voo ao
  /// mesmo tempo (ex.: um filtro mudou enquanto a busca anterior não tinha
  /// resolvido), o próprio `AsyncNotifier`/`invalidateSelf()` garante que só
  /// o resultado mais recente é aplicado — uma resposta antiga nunca
  /// sobrescreve um estado mais novo. Timer próprio (nunca compartilhado com
  /// marca/modelo/responsável, ver [_debounceBusca]).
  void buscar(String texto) {
    _debounceBusca?.cancel();
    _debounceBusca = Timer(const Duration(milliseconds: 300), () {
      _filtro = _filtro.copyWith(busca: texto.trim(), pagina: 0);
      ref.invalidateSelf();
    });
  }

  /// Troca do seletor de campo de busca — dispara nova pesquisa
  /// imediatamente, sem debounce (é uma seleção discreta, não digitação).
  void definirCampoBusca(PatrimonioSearchField campo) {
    _debounceBusca?.cancel();
    _filtro = _filtro.copyWith(campoBusca: campo, pagina: 0);
    ref.invalidateSelf();
  }

  void filtrarPorTipo(String? tipoId) {
    _filtro = _filtro.copyWith(tipoId: tipoId, pagina: 0);
    ref.invalidateSelf();
  }

  void filtrarPorStatus(PatrimonioStatus? status) {
    _filtro = _filtro.copyWith(status: status, pagina: 0);
    ref.invalidateSelf();
  }

  /// Trocar o Setor limpa a Localização selecionada — uma localização de
  /// outra gerência nunca fica "presa" filtrando um resultado que não faz
  /// mais sentido com o novo Setor.
  void filtrarPorSetor(String? setorId) {
    _filtro = _filtro.copyWith(setorId: setorId, localizacaoId: null, semLocalizacao: false, pagina: 0);
    ref.invalidateSelf();
  }

  /// [localizacaoId] `null` com [semLocalizacao] `false` (padrão) significa
  /// "Todas as localizações"; [semLocalizacao] `true` filtra
  /// `localizacao_atual_id IS NULL` — os dois nunca são combinados.
  void filtrarPorLocalizacao(String? localizacaoId, {bool semLocalizacao = false}) {
    _filtro = _filtro.copyWith(
      localizacaoId: semLocalizacao ? null : localizacaoId,
      semLocalizacao: semLocalizacao,
      pagina: 0,
    );
    ref.invalidateSelf();
  }

  /// Filtros avançados textuais — mesmo mecanismo de debounce da busca
  /// principal, mas com um timer PRÓPRIO por campo: independentes
  /// entre si, do campo/termo de busca principal, e de qualquer filtro
  /// imediato trocado enquanto o usuário ainda digita em outro campo.
  void definirMarca(String texto) {
    _debounceMarca?.cancel();
    _debounceMarca = Timer(const Duration(milliseconds: 300), () {
      _filtro = _filtro.copyWith(marca: texto.trim(), pagina: 0);
      ref.invalidateSelf();
    });
  }

  void definirModelo(String texto) {
    _debounceModelo?.cancel();
    _debounceModelo = Timer(const Duration(milliseconds: 300), () {
      _filtro = _filtro.copyWith(modelo: texto.trim(), pagina: 0);
      ref.invalidateSelf();
    });
  }

  void definirResponsavel(String texto) {
    _debounceResponsavel?.cancel();
    _debounceResponsavel = Timer(const Duration(milliseconds: 300), () {
      _filtro = _filtro.copyWith(responsavel: texto.trim(), pagina: 0);
      ref.invalidateSelf();
    });
  }

  /// Datas nunca chegam aqui inválidas: a UI valida (data inicial <= data
  /// final) e só chama este método quando o intervalo é válido — nenhuma
  /// consulta inválida é disparada.
  void definirDataCadastro(DateTime? de, DateTime? ate) {
    _filtro = _filtro.copyWith(dataCadastroDe: de, dataCadastroAte: ate, pagina: 0);
    ref.invalidateSelf();
  }

  void definirDataAquisicao(DateTime? de, DateTime? ate) {
    _filtro = _filtro.copyWith(dataAquisicaoDe: de, dataAquisicaoAte: ate, pagina: 0);
    ref.invalidateSelf();
  }

  /// Trocar o tamanho da página sempre volta para a página 1 — nunca
  /// mantém um número de página que pode não existir mais no novo tamanho.
  void definirTamanhoPagina(int tamanho) {
    _filtro = _filtro.copyWith(tamanhoPagina: tamanho, pagina: 0);
    ref.invalidateSelf();
  }

  /// Clique num cabeçalho/opção de "Ordenar por": campo diferente -> ASC;
  /// mesmo campo em ASC -> DESC; mesmo campo em DESC -> volta à ordenação
  /// padrão (ver [proximoEstadoDeOrdenacao]). Sempre volta para a primeira
  /// página — a ordenação muda o conjunto DE RESULTADOS visível em cada
  /// página, nunca só a página atual.
  void ordenarPor(PatrimonioOrdenacaoCampo campo) {
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

  void limparFiltros() {
    _debounceBusca?.cancel();
    _debounceMarca?.cancel();
    _debounceModelo?.cancel();
    _debounceResponsavel?.cancel();
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
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
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
          localizacaoOrigemId: localizacaoOrigemId,
          localizacaoDestinoId: localizacaoDestinoId,
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
