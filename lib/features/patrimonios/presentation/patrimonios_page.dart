import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../localizacoes/presentation/localizacoes_providers.dart';
import '../../setores/domain/setor.dart';
import '../domain/patrimonio.dart';
import '../domain/patrimonio_detalhe.dart';
import '../domain/patrimonio_ordenacao.dart';
import '../domain/patrimonio_search_field.dart';
import 'patrimonio_reference_data.dart';
import 'patrimonios_controller.dart';
import 'patrimonios_filtro.dart';
import 'patrimonios_view_mode_controller.dart';
import 'widgets/patrimonio_cards_grid.dart';
import 'widgets/patrimonio_desktop_table.dart';
import 'widgets/patrimonio_edit_dialog.dart';
import 'widgets/patrimonio_filters.dart';
import 'widgets/patrimonio_mobile_list.dart';

class PatrimoniosPage extends ConsumerStatefulWidget {
  const PatrimoniosPage({super.key});

  @override
  ConsumerState<PatrimoniosPage> createState() => _PatrimoniosPageState();
}

class _PatrimoniosPageState extends ConsumerState<PatrimoniosPage> {
  final _searchController = TextEditingController();
  PatrimonioSearchField _campoBusca = PatrimonioSearchField.tudo;

  /// Painel de filtros (tipo/status/setor/localização + avançados) abre e
  /// fecha com o botão "Filtros" da [ListPageToolbar] — mesma ideia do
  /// toggle "Filtros avançados" já existente dentro de [PatrimonioFilters],
  /// nunca um popover/overlay flutuante novo.
  bool _filtrosExpandidos = false;

  @override
  void initState() {
    super.initState();
    // Só para atualizar o texto do estado vazio (busca/filtro x cadastro
    // vazio); a consulta em si é disparada com debounce pelo controller.
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _alterarCampoBusca(PatrimonioSearchField campo) {
    setState(() => _campoBusca = campo);
    ref.read(patrimoniosControllerProvider.notifier).definirCampoBusca(campo);
  }

  void _alternarFiltros() => setState(() => _filtrosExpandidos = !_filtrosExpandidos);

  /// Limpar filtros limpa texto + campo de busca (-> Tudo) + Tipo + Status
  /// + Setor — nunca só o lado do controller, senão o texto digitado e o
  /// seletor ficariam visualmente "presos" no valor antigo.
  void _limparFiltros() {
    _searchController.clear();
    setState(() => _campoBusca = PatrimonioSearchField.tudo);
    ref.read(patrimoniosControllerProvider.notifier).limparFiltros();
  }

  void _novoPatrimonio() => context.push('/patrimonios/novo');

  void _importarPlanilha() => context.push('/patrimonios/importar');

  void _abrirDetalhe(String id) => context.push('/patrimonios/$id');

  Future<void> _editar(PatrimonioDetalhe detalhe) async {
    final sucesso = await showPatrimonioEditDialog(context, detalhe: detalhe);
    if (sucesso == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Patrimônio atualizado com sucesso.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
    final canManage =
        perfil == ProfilePerfil.admin ||
        perfil == ProfilePerfil.gestor ||
        perfil == ProfilePerfil.operador;
    final stateAsync = ref.watch(patrimoniosControllerProvider);
    final viewMode =
        ref.watch(patrimoniosViewModeControllerProvider).value ?? ListViewMode.list;
    final termoBusca = _searchController.text.trim();

    // Último filtro conhecido (mesmo durante um `refresh` que mantém o
    // valor anterior em exibição) — a toolbar/controle de ordenação/chips
    // nunca ficam "em branco" só porque uma nova consulta está em voo.
    final filtroAtual = stateAsync.value?.filtro ?? const PatrimoniosFiltro();

    final notifier = ref.read(patrimoniosControllerProvider.notifier);

    final importarButton = canManage
        ? OutlinedButton.icon(
            onPressed: _importarPlanilha,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Importar planilha'),
          )
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSpacing.contentMaxWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InvTecPageHeader(
              title: 'Patrimônios',
              subtitle: 'Consulte e gerencie os equipamentos cadastrados no InvTec.',
            ),
            const SizedBox(height: AppSpacing.md),
            ListPageToolbar(
              searchController: _searchController,
              searchHint:
                  'Buscar por patrimônio, equipamento, série, marca, modelo, responsável...',
              onSearchChanged: (value) =>
                  ref.read(patrimoniosControllerProvider.notifier).buscar(value),
              searchLeading: _CampoBuscaDropdown(
                campoBusca: _campoBusca,
                onChanged: _alterarCampoBusca,
              ),
              filterCount: _contarFiltrosAtivos(filtroAtual),
              onFiltersPressed: _alternarFiltros,
              viewMode: viewMode,
              onViewModeChanged: (modo) =>
                  ref.read(patrimoniosViewModeControllerProvider.notifier).definir(modo),
              primaryActionLabel: canManage ? 'Novo patrimônio' : null,
              primaryActionIcon: canManage ? Icons.add : null,
              onPrimaryAction: canManage ? _novoPatrimonio : null,
              secondaryActions: importarButton != null ? [importarButton] : const [],
            ),
            if (_filtrosExpandidos) ...[
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.smd,
                  ),
                  child: PatrimonioFilters(
                    filtro: filtroAtual,
                    onLimparFiltros: _limparFiltros,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // "Ordenar por" + chips de filtro ativo compartilham a mesma
            // linha quando há espaço (nunca uma barra extra só para os
            // chips) — só quebram em mais de uma sublinha quando realmente
            // não cabem lado a lado.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _OrdenarPorControl(
                  ordenarPor: filtroAtual.ordenarPor,
                  ordenacaoDirecao: filtroAtual.ordenacaoDirecao,
                  onOrdenarPor: notifier.ordenarPor,
                ),
                if (filtroAtual.temFiltroAtivo) _ActiveFilterChips(filtro: filtroAtual),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            stateAsync.when(
              data: (state) {
                final itens = state.resultado.itens;
                if (itens.isEmpty) {
                  return _EmptyList(
                    temFiltroOuBusca:
                        state.filtro.temFiltroAtivo || termoBusca.isNotEmpty,
                    termoBusca: termoBusca,
                    correspondenciasPorNumeroSerie:
                        state.resultado.correspondenciasPorNumeroSerie.length,
                    onVerCorrespondenciaSerie: () =>
                        _alterarCampoBusca(PatrimonioSearchField.numeroSerie),
                    canManage: canManage,
                    onNovoPatrimonio: _novoPatrimonio,
                  );
                }

                final Widget conteudo;
                if (context.screenSize == ScreenSize.mobile) {
                  // Mobile sempre usa a lista em 1 coluna — uma "lista" ou
                  // "cards em grade" pensada para desktop nunca tenta caber
                  // numa tela estreita, independente do ListViewMode salvo.
                  conteudo = PatrimonioMobileList(
                    itens: itens,
                    canManage: canManage,
                    onTap: (item) => _abrirDetalhe(item.patrimonio.id),
                    onEdit: _editar,
                  );
                } else if (viewMode == ListViewMode.cards) {
                  conteudo = PatrimonioCardsGrid(
                    itens: itens,
                    canManage: canManage,
                    onTap: (item) => _abrirDetalhe(item.patrimonio.id),
                    onEdit: _editar,
                  );
                } else {
                  conteudo = PatrimonioDesktopTable(
                    itens: itens,
                    canManage: canManage,
                    ordenarPor: state.filtro.ordenarPor,
                    ordenacaoDirecao: state.filtro.ordenacaoDirecao,
                    onOrdenarPor: notifier.ordenarPor,
                    onTap: (item) => _abrirDetalhe(item.patrimonio.id),
                    onEdit: _editar,
                  );
                }

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
                      tamanhosPaginaPermitidos: patrimoniosTamanhosPaginaPermitidos,
                      onChanged: (pagina) => ref
                          .read(patrimoniosControllerProvider.notifier)
                          .irParaPagina(pagina),
                      onTamanhoPaginaChanged: (tamanho) => ref
                          .read(patrimoniosControllerProvider.notifier)
                          .definirTamanhoPagina(tamanho),
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
                  message:
                      'Não foi possível acessar os patrimônios. Tente novamente.',
                  actionLabel: 'Tentar novamente',
                  onAction: () => ref
                      .read(patrimoniosControllerProvider.notifier)
                      .recarregar(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quantos filtros principais + avançados estão ativos — usado no contador
/// "Filtros (N)" da [ListPageToolbar]. Cada filtro principal ativo conta
/// como 1 (localização e "sem localização" nunca somam juntos — são
/// mutuamente exclusivos); os avançados já vêm contados por
/// [PatrimoniosFiltro.quantidadeFiltrosAvancados].
int _contarFiltrosAtivos(PatrimoniosFiltro filtro) {
  var quantidade = filtro.quantidadeFiltrosAvancados;
  if (filtro.tipoId != null) quantidade++;
  if (filtro.status != null) quantidade++;
  if (filtro.setorId != null) quantidade++;
  if (filtro.localizacaoId != null || filtro.semLocalizacao) quantidade++;
  return quantidade;
}

/// Seletor "Buscar em" — vive DENTRO do campo de busca da
/// [ListPageToolbar] (via [ListPageToolbar.searchLeading]), por isso não tem
/// borda/decoração própria: a largura acompanha o valor selecionado (nunca
/// um retângulo fixo estreito demais, que truncava rótulos como "Marca /
/// Modelo" em "Busc..."). O rótulo "Buscar em" em si vira só um [Tooltip] —
/// o valor sempre aparece por extenso ("Tudo", "Patrimônio", ...).
class _CampoBuscaDropdown extends StatelessWidget {
  const _CampoBuscaDropdown({required this.campoBusca, required this.onChanged});

  final PatrimonioSearchField campoBusca;
  final ValueChanged<PatrimonioSearchField> onChanged;

  @override
  Widget build(BuildContext context) {
    // Largura FIXA (não intrínseca): sem isto, `DropdownButton` mede sua
    // largura pelo maior rótulo entre TODAS as opções (ex.: "Equipamento /
    // Descrição"), não só a selecionada — "Tudo" ficaria com um espaço vazio
    // enorme reservado, e em telas estreitas o próprio seletor estoura.
    // `isExpanded` + `overflow: ellipsis` fazem o rótulo selecionado caber
    // nessa largura (reticências só no raro caso de um rótulo longo numa
    // tela muito estreita — nunca uma única letra truncada).
    return Tooltip(
      message: 'Buscar em',
      child: SizedBox(
        width: 128,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<PatrimonioSearchField>(
            value: campoBusca,
            isDense: true,
            isExpanded: true,
            borderRadius: BorderRadius.circular(8),
            items: [
              for (final campo in PatrimonioSearchField.values)
                DropdownMenuItem(
                  value: campo,
                  child: Text(campo.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (campo) {
              if (campo != null) onChanged(campo);
            },
          ),
        ),
      ),
    );
  }
}

/// Controle "Ordenar por: [ campo ▾ ] [↑/↓]" — sempre visível (Lista e
/// Cards, desktop e mobile), já que Marca/Localização/Data de cadastro não
/// têm cabeçalho clicável próprio. Usa o MESMO [onOrdenarPor] (o método
/// `PatrimoniosController.ordenarPor`) que os cliques de cabeçalho da
/// tabela — nunca um segundo estado de ordenação paralelo. Clicar no ícone
/// de direção reaplica o campo já selecionado, o que segue o mesmo ciclo
/// ASC -> DESC -> padrão de um clique de cabeçalho (ver
/// `proximoEstadoDeOrdenacao`).
class _OrdenarPorControl extends StatelessWidget {
  const _OrdenarPorControl({
    required this.ordenarPor,
    required this.ordenacaoDirecao,
    required this.onOrdenarPor,
  });

  final PatrimonioOrdenacaoCampo? ordenarPor;
  final OrdenacaoDirecao ordenacaoDirecao;
  final ValueChanged<PatrimonioOrdenacaoCampo> onOrdenarPor;

  @override
  Widget build(BuildContext context) {
    final direcaoDescricao = ordenarPor == null
        ? 'Ordenação padrão (cadastro mais recente primeiro)'
        : ordenacaoDirecao == OrdenacaoDirecao.asc
        ? 'Ordem crescente — clique para inverter'
        : 'Ordem decrescente — clique para inverter';

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        Text('Ordenar por:', style: AppTypography.auxiliary(context)),
        DropdownButton<PatrimonioOrdenacaoCampo?>(
          value: ordenarPor,
          hint: const Text('Padrão'),
          underline: const SizedBox.shrink(),
          // Sem isto, o destaque de hover/focus/toque do próprio botão
          // (não só do menu) sai com cantos retos, cobrindo toda a área do
          // texto + seta — destoando de um controle sem borda visível.
          borderRadius: BorderRadius.circular(8),
          items: [
            for (final campo in PatrimonioOrdenacaoCampo.values)
              DropdownMenuItem(value: campo, child: Text(campo.label)),
          ],
          onChanged: (campo) {
            if (campo != null) onOrdenarPor(campo);
          },
        ),
        CompactIconButton(
          tooltip: direcaoDescricao,
          iconSize: 18,
          icon: Icon(
            ordenacaoDirecao == OrdenacaoDirecao.asc
                ? Icons.arrow_upward
                : Icons.arrow_downward,
          ),
          onPressed: ordenarPor == null ? null : () => onOrdenarPor(ordenarPor!),
        ),
      ],
    );
  }
}

/// Uma linha de [ActiveFilterChip] por filtro ativo (principal + avançado),
/// cada um removendo SÓ o seu próprio filtro — nunca aparece quando nenhum
/// filtro está ativo. Os nomes de Tipo/Setor/Localização são resolvidos a
/// partir do id salvo no filtro, usando os MESMOS providers que
/// [PatrimonioFilters] já usa para os dropdowns (nunca uma segunda fonte de
/// dados que poderia divergir).
class _ActiveFilterChips extends ConsumerWidget {
  const _ActiveFilterChips({required this.filtro});

  final PatrimoniosFiltro filtro;

  String? _nomePorId<T>(
    AsyncValue<List<T>> async,
    String? id,
    String Function(T) nome,
    String Function(T) idDe,
  ) {
    if (id == null) return null;
    return async.maybeWhen(
      data: (lista) {
        for (final item in lista) {
          if (idDe(item) == id) return nome(item);
        }
        return null;
      },
      orElse: () => null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!filtro.temFiltroAtivo) return const SizedBox.shrink();

    final notifier = ref.read(patrimoniosControllerProvider.notifier);
    final tiposAsync = ref.watch(tiposAtivosProvider);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);
    final localizacoesAsync = ref.watch(localizacoesParaFiltroProvider(filtro.setorId));

    final nomeTipo = _nomePorId(tiposAsync, filtro.tipoId, (t) => t.nome, (t) => t.id);
    final nomeSetor = _nomePorId(
      setoresAsync,
      filtro.setorId,
      (s) => s.rotuloCompacto,
      (s) => s.id,
    );
    final nomeLocalizacao = _nomePorId(
      localizacoesAsync,
      filtro.localizacaoId,
      (l) => l.nome,
      (l) => l.id,
    );

    final chips = <Widget>[
      if (filtro.tipoId != null)
        ActiveFilterChip(
          label: 'Tipo: ${nomeTipo ?? '...'}',
          onRemove: () => notifier.filtrarPorTipo(null),
        ),
      if (filtro.status != null)
        ActiveFilterChip(
          label: 'Status: ${filtro.status!.label}',
          onRemove: () => notifier.filtrarPorStatus(null),
        ),
      if (filtro.setorId != null)
        ActiveFilterChip(
          label: 'Setor: ${nomeSetor ?? '...'}',
          onRemove: () => notifier.filtrarPorSetor(null),
        ),
      if (filtro.semLocalizacao)
        ActiveFilterChip(
          label: 'Sem localização',
          onRemove: () => notifier.filtrarPorLocalizacao(null),
        ),
      if (!filtro.semLocalizacao && filtro.localizacaoId != null)
        ActiveFilterChip(
          label: 'Localização: ${nomeLocalizacao ?? '...'}',
          onRemove: () => notifier.filtrarPorLocalizacao(null),
        ),
      if (filtro.marca.isNotEmpty)
        ActiveFilterChip(
          label: 'Marca: ${filtro.marca}',
          onRemove: () => notifier.definirMarca(''),
        ),
      if (filtro.modelo.isNotEmpty)
        ActiveFilterChip(
          label: 'Modelo: ${filtro.modelo}',
          onRemove: () => notifier.definirModelo(''),
        ),
      if (filtro.responsavel.isNotEmpty)
        ActiveFilterChip(
          label: 'Responsável: ${filtro.responsavel}',
          onRemove: () => notifier.definirResponsavel(''),
        ),
      if (filtro.dataCadastroDe != null || filtro.dataCadastroAte != null)
        ActiveFilterChip(
          label: 'Cadastro: ${_formatarIntervalo(filtro.dataCadastroDe, filtro.dataCadastroAte)}',
          onRemove: () => notifier.definirDataCadastro(null, null),
        ),
      if (filtro.dataAquisicaoDe != null || filtro.dataAquisicaoAte != null)
        ActiveFilterChip(
          label:
              'Aquisição: ${_formatarIntervalo(filtro.dataAquisicaoDe, filtro.dataAquisicaoAte)}',
          onRemove: () => notifier.definirDataAquisicao(null, null),
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    // Sem `Padding` própria: quem posiciona este bloco é o `Wrap` externo
    // que o combina com "Ordenar por" (mesma linha, quando cabe).
    return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: chips);
  }
}

String _formatarData(DateTime data) =>
    '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

String _formatarIntervalo(DateTime? de, DateTime? ate) {
  if (de != null && ate != null) return '${_formatarData(de)} – ${_formatarData(ate)}';
  if (de != null) return 'a partir de ${_formatarData(de)}';
  if (ate != null) return 'até ${_formatarData(ate)}';
  return '';
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({
    required this.temFiltroOuBusca,
    required this.termoBusca,
    required this.correspondenciasPorNumeroSerie,
    required this.onVerCorrespondenciaSerie,
    required this.canManage,
    required this.onNovoPatrimonio,
  });

  final bool temFiltroOuBusca;
  final String termoBusca;

  /// Quantidade de patrimônios cujo NÚMERO DE SÉRIE (nunca o número de
  /// patrimônio) coincide com [termoBusca] — só populado quando não há
  /// nenhum patrimônio com esse número exato. Nunca aparece misturado com
  /// a listagem principal, nem é apresentado como se fosse "o patrimônio
  /// pesquisado".
  final int correspondenciasPorNumeroSerie;
  final VoidCallback onVerCorrespondenciaSerie;
  final bool canManage;
  final VoidCallback onNovoPatrimonio;

  @override
  Widget build(BuildContext context) {
    if (temFiltroOuBusca) {
      // Mensagem específica com o termo digitado, quando houver — nunca
      // uma mensagem genérica que esconda o que foi pesquisado.
      final mensagem = termoBusca.isEmpty
          ? 'Nenhum patrimônio encontrado.'
          : correspondenciasPorNumeroSerie > 0
          // Deixa explícito que o termo NÃO é o número de um patrimônio
          // encontrado — nunca silenciosamente mostrar outro patrimônio
          // como se fosse a resposta.
          ? 'Nenhum patrimônio nº "$termoBusca" encontrado.'
          : 'Nenhum patrimônio encontrado para "$termoBusca".';
      return Card(
        child: Column(
          children: [
            EmptyState(icon: Icons.search_off, message: mensagem),
            if (correspondenciasPorNumeroSerie > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            correspondenciasPorNumeroSerie == 1
                                ? '1 equipamento possui "$termoBusca" como número de série.'
                                : '$correspondenciasPorNumeroSerie equipamentos possuem "$termoBusca" como número de série.',
                          ),
                        ),
                        TextButton(
                          onPressed: onVerCorrespondenciaSerie,
                          child: const Text('Ver resultado'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Card(
      child: EmptyState(
        icon: Icons.inventory_2_outlined,
        message:
            'Nenhum patrimônio cadastrado.\nCadastre o primeiro equipamento '
            'para começar o controle patrimonial.',
        actionLabel: canManage ? 'Cadastrar patrimônio' : null,
        onAction: canManage ? onNovoPatrimonio : null,
      ),
    );
  }
}
