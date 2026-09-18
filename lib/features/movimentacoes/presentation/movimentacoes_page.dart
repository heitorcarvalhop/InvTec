import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/movimentacao_listagem_item.dart';
import 'movimentacoes_controller.dart';
import 'movimentacoes_filtro.dart';
import 'widgets/movimentacao_detail_dialog.dart';
import 'widgets/movimentacoes_desktop_table.dart';
import 'widgets/movimentacoes_filters.dart';
import 'widgets/movimentacoes_mobile_list.dart';
import 'widgets/nova_movimentacao_dialog.dart';
import '../sei/presentation/importar_sei_dialog.dart';

/// Listagem geral de movimentações (PROMPT 10.1) — somente leitura: nesta
/// etapa não há criar/editar/excluir, só consultar o histórico já
/// registrado pelas telas de patrimônio.
class MovimentacoesPage extends ConsumerStatefulWidget {
  const MovimentacoesPage({super.key});

  @override
  ConsumerState<MovimentacoesPage> createState() => _MovimentacoesPageState();
}

class _MovimentacoesPageState extends ConsumerState<MovimentacoesPage> {
  final _searchController = TextEditingController();

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

  Future<void> _importarDocumentoSei() => showImportarSeiDialog(context);

  @override
  Widget build(BuildContext context) {
    // Mesma checagem de perfil usada em Patrimônios/Setores (PROMPT 10.2,
    // seção 2): ADMIN/GESTOR/OPERADOR podem registrar — CONSULTA nunca
    // recebe uma ação de escrita, mesmo que só visual (a RPC também nega,
    // mas o botão nem aparece).
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
              // "Importar documento SEI" (PROMPT 11.1, seção 3) é uma ação
              // SECUNDÁRIA e somente leitura — nesta versão nenhum perfil
              // registra movimentações por ali (o assistente nem tem acesso
              // a `MovimentacaoRepository`, ver `SeiImportController`), mas
              // ainda assim fica atrás da mesma checagem de perfil de
              // "Nova movimentação": nenhuma mudança de RLS foi feita para
              // isso, e CONSULTA continua sem nenhuma ação aqui até essa
              // decisão ser revisitada.
              actions: canManage
                  ? [
                      OutlinedButton.icon(
                        onPressed: _importarDocumentoSei,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Importar documento SEI'),
                      ),
                      FilledButton.icon(
                        onPressed: _novaMovimentacao,
                        icon: const Icon(Icons.add),
                        label: const Text('Nova movimentação'),
                      ),
                    ]
                  : const [],
            ),
            const SizedBox(height: AppSpacing.md),
            // Mesmo painel de busca+filtros de Patrimônios/Setores (PROMPT
            // 9.3.3): tudo agrupado numa única superfície coesa.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SearchField(
                      controller: _searchController,
                      onChanged: (value) => ref.read(movimentacoesControllerProvider.notifier).buscar(value),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    stateAsync.maybeWhen(
                      data: (state) => MovimentacoesFilters(
                        filtro: state.filtro,
                        onLimparFiltros: _limparFiltros,
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
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

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    context.screenSize == ScreenSize.mobile
                        ? MovimentacoesMobileList(itens: itens, onVisualizar: _visualizar)
                        : MovimentacoesDesktopTable(itens: itens, onVisualizar: _visualizar),
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
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por patrimônio, responsável, documento ou chamado...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
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
      return Card(child: EmptyState(icon: Icons.search_off, message: mensagem));
    }

    return const Card(
      child: EmptyState(
        icon: Icons.swap_horiz_outlined,
        message: 'Nenhuma movimentação registrada ainda.',
      ),
    );
  }
}
