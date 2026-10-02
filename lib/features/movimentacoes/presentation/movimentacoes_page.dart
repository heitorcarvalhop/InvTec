import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/ordenacao_direcao.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/active_filter_chip.dart';
import '../../../core/widgets/compact_icon_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_page_toolbar.dart';
import '../../../core/widgets/list_view_mode.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../setores/domain/setor.dart';
import '../domain/movimentacao.dart';
import '../domain/movimentacao_listagem_item.dart';
import '../domain/movimentacao_ordenacao.dart';
import 'movimentacoes_controller.dart';
import 'movimentacoes_filtro.dart';
import 'movimentacoes_reference_data.dart';
import 'movimentacoes_view_mode_controller.dart';
import 'widgets/movimentacao_cards_grid.dart';
import 'widgets/movimentacao_detail_dialog.dart';
import 'widgets/movimentacoes_desktop_table.dart';
import 'widgets/movimentacoes_filters.dart';
import 'widgets/movimentacoes_mobile_list.dart';
import 'widgets/nova_movimentacao_dialog.dart';
import '../sei/presentation/importar_sei_dialog.dart';
import '../sei/presentation/widgets/sei_pendencias_section.dart';

/// Listagem geral de movimentações — somente leitura: não há criar/editar/
/// excluir aqui, só consultar o histórico já registrado pelas telas de
/// patrimônio.
class MovimentacoesPage extends ConsumerStatefulWidget {
  const MovimentacoesPage({super.key});

  @override
  ConsumerState<MovimentacoesPage> createState() => _MovimentacoesPageState();
}

/// Abas da tela: "Pendências / Documentos SEI" fica SEPARADA de "Histórico
/// de movimentações" — documentos pendentes nunca entram no histórico de
/// `movimentacoes`, então a aba de pendências lê exclusivamente
/// `DocumentosSeiRepository`, nunca `MovimentacaoRepository`.
enum _MovimentacoesAba { historico, pendencias }

class _MovimentacoesPageState extends ConsumerState<MovimentacoesPage> {
  final _searchController = TextEditingController();
  _MovimentacoesAba _aba = _MovimentacoesAba.historico;

  /// Painel de filtros (tipo/setor/período) começa fechado — a
  /// `ListPageToolbar` só é dona do botão/contador, cada tela decide se
  /// começa aberta ou fechada (aqui, igual Patrimônios: fechada, para não
  /// disputar espaço com a tabela/cards logo de cara).
  bool _filtrosExpandidos = false;

  // A aba de pendências só é CONSTRUÍDA (e só então dispara a consulta ao
  // `DocumentosSeiRepository`) depois de visitada pelo menos uma vez —
  // nunca no primeiro build da tela.
  bool _pendenciasVisitada = false;

  @override
  void initState() {
    super.initState();
    // Só para atualizar o texto do estado vazio (busca x nenhuma
    // movimentação); a consulta em si é disparada com debounce pelo
    // controller.
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _limparFiltros() {
    _searchController.clear();
    ref.read(movimentacoesControllerProvider.notifier).limparFiltros();
  }

  void _visualizar(MovimentacaoListagemItem item) => showMovimentacaoDetailDialog(context, item);

  Future<void> _novaMovimentacao() async {
    final sucesso = await showNovaMovimentacaoDialog(context);
    if (sucesso == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Movimentação registrada com sucesso.')));
    }
  }

  Future<void> _importarDocumentoSei() async {
    // "Salvar como pendência" no assistente devolve `true` quando a
    // solicitação foi efetivamente persistida — NUNCA significa que uma
    // movimentação foi registrada.
    final salvouPendencia = await showImportarSeiDialog(context);
    if (salvouPendencia == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Solicitação salva como pendência. Nenhuma movimentação foi registrada.')),
        );
      setState(() => _aba = _MovimentacoesAba.pendencias);
    }
  }

  void _selecionarAba(_MovimentacoesAba aba) {
    setState(() {
      _aba = aba;
      if (aba == _MovimentacoesAba.pendencias) _pendenciasVisitada = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mesma checagem de perfil usada em Patrimônios/Setores: ADMIN/GESTOR/
    // OPERADOR podem registrar — CONSULTA nunca recebe uma ação de escrita,
    // mesmo que só visual (a RPC também nega, mas o botão nem aparece).
    final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
    final canManage =
        perfil == ProfilePerfil.admin || perfil == ProfilePerfil.gestor || perfil == ProfilePerfil.operador;
    final stateAsync = ref.watch(movimentacoesControllerProvider);
    final termoBusca = _searchController.text.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InvTecPageHeader(
              title: 'Movimentações',
              subtitle: 'Consulte e acompanhe o histórico de movimentações patrimoniais.',
              compact: context.screenSize == ScreenSize.mobile,
            ),
            const SizedBox(height: AppSpacing.md),
            // Duas seções distintas — "Pendências / Documentos SEI" nunca
            // mistura com o histórico de movimentações efetivamente
            // registradas.
            SegmentedButton<_MovimentacoesAba>(
              segments: const [
                ButtonSegment(
                  value: _MovimentacoesAba.historico,
                  label: Text('Histórico de movimentações'),
                  icon: Icon(Icons.history),
                ),
                ButtonSegment(
                  value: _MovimentacoesAba.pendencias,
                  label: Text('Pendências / Documentos SEI'),
                  icon: Icon(Icons.pending_actions_outlined),
                ),
              ],
              selected: {_aba},
              onSelectionChanged: (selecionados) => _selecionarAba(selecionados.first),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_aba == _MovimentacoesAba.historico) ...[
              // Toolbar compartilhada (busca + filtros + Lista/Cards + ação
              // principal) — só nesta aba: "Nova movimentação"/"Importar
              // documento SEI" nunca aparecem em "Pendências / Documentos
              // SEI".
              stateAsync.maybeWhen(
                data: (state) => _HistoricoControles(
                  filtro: state.filtro,
                  searchController: _searchController,
                  onSearchChanged: (value) => ref.read(movimentacoesControllerProvider.notifier).buscar(value),
                  filtrosExpandidos: _filtrosExpandidos,
                  onFiltrosPressed: () => setState(() => _filtrosExpandidos = !_filtrosExpandidos),
                  onLimparFiltros: _limparFiltros,
                  canManage: canManage,
                  onNovaMovimentacao: _novaMovimentacao,
                  onImportarDocumentoSei: _importarDocumentoSei,
                  onOrdenarPor: (campo) => ref.read(movimentacoesControllerProvider.notifier).ordenarPor(campo),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.lg),
              stateAsync.when(
                data: (state) {
                  final itens = state.resultado.itens;
                  if (itens.isEmpty) {
                    return _EmptyList(
                      temFiltroOuBusca: state.filtro.temFiltroAtivo || termoBusca.isNotEmpty,
                      termoBusca: termoBusca,
                    );
                  }

                  final viewModeAsync = ref.watch(movimentacoesViewModeControllerProvider);
                  final viewMode = viewModeAsync.value ?? ListViewMode.list;
                  // Mobile SEMPRE usa a lista compacta de 1 coluna,
                  // independente da preferência de Lista/Cards salva — o
                  // grid de cards (pensado para tablet/desktop) nunca cabe
                  // bem numa tela de celular.
                  final conteudo = context.screenSize == ScreenSize.mobile
                      ? MovimentacoesMobileList(itens: itens, onVisualizar: _visualizar)
                      : viewMode == ListViewMode.list
                      ? MovimentacoesDesktopTable(
                          itens: itens,
                          onVisualizar: _visualizar,
                          ordenarPor: state.filtro.ordenarPor,
                          ordenacaoDirecao: state.filtro.ordenacaoDirecao,
                          onOrdenarPor: (campo) =>
                              ref.read(movimentacoesControllerProvider.notifier).ordenarPor(campo),
                        )
                      : MovimentacaoCardsGrid(itens: itens, onVisualizar: _visualizar);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      conteudo,
                      const SizedBox(height: AppSpacing.lg),
                      PaginationControls(
                        paginaAtual: state.filtro.pagina,
                        totalPaginas: state.totalPaginas,
                        totalItens: state.resultado.total,
                        tamanhoPagina: state.filtro.tamanhoPagina,
                        tamanhosPaginaPermitidos: movimentacoesTamanhosPaginaPermitidos,
                        onChanged: (pagina) => ref.read(movimentacoesControllerProvider.notifier).irParaPagina(pagina),
                        onTamanhoPaginaChanged: (tamanho) =>
                            ref.read(movimentacoesControllerProvider.notifier).definirTamanhoPagina(tamanho),
                      ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => Center(
                  child: EmptyState(
                    icon: Icons.error_outline,
                    message: 'Não foi possível acessar as movimentações. Tente novamente.',
                    actionLabel: 'Tentar novamente',
                    onAction: () => ref.read(movimentacoesControllerProvider.notifier).recarregar(),
                  ),
                ),
              ),
            ] else if (_pendenciasVisitada)
              const SeiPendenciasSection(),
          ],
        ),
      ),
    );
  }
}

/// Toolbar + painel de filtros expansível + chips de filtro ativo + o
/// controle "Ordenar por" — tudo que fica acima da tabela/grid da aba
/// Histórico, reunido num único widget para o `build` principal não ficar
/// gigante.
class _HistoricoControles extends ConsumerWidget {
  const _HistoricoControles({
    required this.filtro,
    required this.searchController,
    required this.onSearchChanged,
    required this.filtrosExpandidos,
    required this.onFiltrosPressed,
    required this.onLimparFiltros,
    required this.canManage,
    required this.onNovaMovimentacao,
    required this.onImportarDocumentoSei,
    required this.onOrdenarPor,
  });

  final MovimentacoesFiltro filtro;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool filtrosExpandidos;
  final VoidCallback onFiltrosPressed;
  final VoidCallback onLimparFiltros;
  final bool canManage;
  final VoidCallback onNovaMovimentacao;
  final VoidCallback onImportarDocumentoSei;
  final ValueChanged<MovimentacaoOrdenacaoCampo> onOrdenarPor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModeAsync = ref.watch(movimentacoesViewModeControllerProvider);
    final viewMode = viewModeAsync.value ?? ListViewMode.list;
    final setoresAsync = ref.watch(setoresParaFiltroMovimentacoesProvider);

    final botaoImportarSei = canManage
        ? OutlinedButton.icon(
            onPressed: onImportarDocumentoSei,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Importar documento SEI'),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListPageToolbar(
          searchController: searchController,
          searchHint: 'Buscar por patrimônio, equipamento, documento, chamado, responsável...',
          onSearchChanged: onSearchChanged,
          filterCount: _contarFiltrosAtivos(filtro),
          onFiltersPressed: onFiltrosPressed,
          viewMode: viewMode,
          onViewModeChanged: (modo) => ref.read(movimentacoesViewModeControllerProvider.notifier).definir(modo),
          primaryActionLabel: canManage ? 'Nova movimentação' : null,
          primaryActionIcon: canManage ? Icons.add : null,
          onPrimaryAction: canManage ? onNovaMovimentacao : null,
          secondaryActions: botaoImportarSei != null ? [botaoImportarSei] : const [],
        ),
        if (filtrosExpandidos) ...[
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: MovimentacoesFilters(filtro: filtro, onLimparFiltros: onLimparFiltros),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        // "Ordenar por" + chips de filtro ativo compartilham a mesma linha
        // quando há espaço (nunca uma barra extra só para os chips).
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            _OrdenarPorControl(filtro: filtro, onOrdenarPor: onOrdenarPor),
            if (filtro.temFiltroAtivo) _ActiveFilterChipsRow(filtro: filtro, setores: setoresAsync.value),
          ],
        ),
      ],
    );
  }
}

int _contarFiltrosAtivos(MovimentacoesFiltro filtro) {
  var contador = 0;
  if (filtro.tipo != null) contador++;
  if (filtro.setorId != null) contador++;
  if (filtro.periodoDe != null) contador++;
  if (filtro.periodoAte != null) contador++;
  return contador;
}

/// Linha de `ActiveFilterChip` abaixo da toolbar — só aparece quando há
/// filtro ativo (tipo/setor/período; a busca livre não entra aqui, ela já
/// aparece no próprio campo de busca). Cada chip remove só o seu filtro,
/// nunca os outros.
class _ActiveFilterChipsRow extends ConsumerWidget {
  const _ActiveFilterChipsRow({required this.filtro, required this.setores});

  final MovimentacoesFiltro filtro;
  final List<Setor>? setores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(movimentacoesControllerProvider.notifier);
    final chips = <Widget>[];

    if (filtro.tipo != null) {
      chips.add(
        ActiveFilterChip(label: 'Tipo: ${filtro.tipo!.label}', onRemove: () => notifier.filtrarPorTipo(null)),
      );
    }
    if (filtro.setorId != null) {
      final setor = _encontrarSetor(setores, filtro.setorId);
      chips.add(
        ActiveFilterChip(
          label: 'Setor: ${setor?.rotuloCompacto ?? 'selecionado'}',
          onRemove: () => notifier.filtrarPorSetor(null),
        ),
      );
    }
    if (filtro.periodoDe != null || filtro.periodoAte != null) {
      chips.add(
        ActiveFilterChip(
          label: 'Período: ${_rotuloPeriodo(filtro.periodoDe, filtro.periodoAte)}',
          onRemove: () => notifier.definirPeriodo(null, null),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    // Sem `Padding` própria: quem posiciona este bloco é o `Wrap` externo
    // que o combina com "Ordenar por" (mesma linha, quando cabe).
    return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: chips);
  }
}

Setor? _encontrarSetor(List<Setor>? setores, String? id) {
  if (setores == null || id == null) return null;
  for (final setor in setores) {
    if (setor.id == id) return setor;
  }
  return null;
}

String _rotuloPeriodo(DateTime? de, DateTime? ate) {
  if (de != null && ate != null) return '${_formatarDataCurta(de)} – ${_formatarDataCurta(ate)}';
  if (de != null) return 'A partir de ${_formatarDataCurta(de)}';
  return 'Até ${_formatarDataCurta(ate!)}';
}

String _formatarDataCurta(DateTime data) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(data.day)}/${pad(data.month)}/${data.year}';
}

/// "Ordenar por: [ seletor ] [↑/↓]" — mesmo estado de ordenação dos
/// cabeçalhos clicáveis da tabela (nunca duas ordenações paralelas);
/// sempre visível, tanto em Lista quanto em Cards, já que o modo Cards não
/// tem cabeçalho de coluna para clicar.
class _OrdenarPorControl extends StatelessWidget {
  const _OrdenarPorControl({required this.filtro, required this.onOrdenarPor});

  final MovimentacoesFiltro filtro;
  final ValueChanged<MovimentacaoOrdenacaoCampo> onOrdenarPor;

  @override
  Widget build(BuildContext context) {
    // `null` é a ordenação padrão da tela (data mais recente primeiro) —
    // aqui exibida já como "Data" + seta decrescente, para o controle
    // nunca aparecer "em branco".
    final campoAtual = filtro.ordenarPor ?? MovimentacaoOrdenacaoCampo.data;
    final direcaoAtual = filtro.ordenarPor == null ? OrdenacaoDirecao.desc : filtro.ordenacaoDirecao;
    final ascendente = direcaoAtual == OrdenacaoDirecao.asc;

    return Wrap(
      spacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Ordenar por:', style: AppTypography.label(context)),
        DropdownButton<MovimentacaoOrdenacaoCampo>(
          value: campoAtual,
          underline: const SizedBox.shrink(),
          // Sem isto, o destaque de hover/focus/toque do próprio botão
          // (não só do menu) sai com cantos retos — ver mesmo ajuste em
          // `patrimonios_page.dart`.
          borderRadius: BorderRadius.circular(8),
          items: [
            for (final campo in MovimentacaoOrdenacaoCampo.values)
              DropdownMenuItem(value: campo, child: Text(campo.label)),
          ],
          onChanged: (campo) {
            if (campo != null) onOrdenarPor(campo);
          },
        ),
        CompactIconButton(
          tooltip: ascendente ? 'Ordem crescente' : 'Ordem decrescente',
          icon: Icon(ascendente ? Icons.arrow_upward : Icons.arrow_downward),
          onPressed: () => onOrdenarPor(campoAtual),
        ),
      ],
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.temFiltroOuBusca, required this.termoBusca});

  final bool temFiltroOuBusca;
  final String termoBusca;

  @override
  Widget build(BuildContext context) {
    if (temFiltroOuBusca) {
      final mensagem = termoBusca.isEmpty
          ? 'Nenhuma movimentação encontrada.'
          : 'Nenhuma movimentação encontrada para "$termoBusca".';
      return Card(
        child: EmptyState(icon: Icons.search_off, message: mensagem),
      );
    }

    return const Card(
      child: EmptyState(icon: Icons.swap_horiz_outlined, message: 'Nenhuma movimentação registrada ainda.'),
    );
  }
}
