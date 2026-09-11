import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/patrimonio_detalhe.dart';
import 'patrimonios_controller.dart';
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
    final termoBusca = _searchController.text.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSpacing.contentMaxWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              canManage: canManage,
              onNovoPatrimonio: _novoPatrimonio,
              onImportarPlanilha: _importarPlanilha,
            ),
            const SizedBox(height: AppSpacing.md),
            _SearchField(
              controller: _searchController,
              onChanged: (value) => ref
                  .read(patrimoniosControllerProvider.notifier)
                  .buscar(value),
            ),
            const SizedBox(height: AppSpacing.md),
            stateAsync.maybeWhen(
              data: (state) => PatrimonioFilters(filtro: state.filtro),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.lg),
            stateAsync.when(
              data: (state) {
                final itens = state.resultado.itens;
                if (itens.isEmpty) {
                  return _EmptyList(
                    temFiltroOuBusca:
                        state.filtro.temFiltroAtivo || termoBusca.isNotEmpty,
                    canManage: canManage,
                    onNovoPatrimonio: _novoPatrimonio,
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    context.screenSize == ScreenSize.mobile
                        ? PatrimonioMobileList(
                            itens: itens,
                            onTap: (item) =>
                                _abrirDetalhe(item.patrimonio.id),
                          )
                        : PatrimonioDesktopTable(
                            itens: itens,
                            canManage: canManage,
                            onTap: (item) =>
                                _abrirDetalhe(item.patrimonio.id),
                            onEdit: _editar,
                          ),
                    if (state.totalPaginas > 1) ...[
                      const SizedBox(height: AppSpacing.lg),
                      PaginationControls(
                        paginaAtual: state.filtro.pagina,
                        totalPaginas: state.totalPaginas,
                        onChanged: (pagina) => ref
                            .read(patrimoniosControllerProvider.notifier)
                            .irParaPagina(pagina),
                      ),
                    ],
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

class _Header extends StatelessWidget {
  const _Header({
    required this.canManage,
    required this.onNovoPatrimonio,
    required this.onImportarPlanilha,
  });

  final bool canManage;
  final VoidCallback onNovoPatrimonio;
  final VoidCallback onImportarPlanilha;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Patrimônios', style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Consulte e gerencie os equipamentos cadastrados no InvTec.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final botoes = Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          onPressed: onImportarPlanilha,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Importar planilha'),
        ),
        FilledButton.icon(
          onPressed: onNovoPatrimonio,
          icon: const Icon(Icons.add),
          label: const Text('Novo patrimônio'),
        ),
      ],
    );

    if (!canManage) return titulo;

    if (context.screenSize == ScreenSize.mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titulo, const SizedBox(height: AppSpacing.md), botoes],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titulo),
        const SizedBox(width: AppSpacing.md),
        botoes,
      ],
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
        hintText: 'Buscar por número, série, marca ou modelo',
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
  const _EmptyList({
    required this.temFiltroOuBusca,
    required this.canManage,
    required this.onNovoPatrimonio,
  });

  final bool temFiltroOuBusca;
  final bool canManage;
  final VoidCallback onNovoPatrimonio;

  @override
  Widget build(BuildContext context) {
    if (temFiltroOuBusca) {
      return const Card(
        child: EmptyState(
          icon: Icons.search_off,
          message: 'Nenhum patrimônio encontrado para os critérios informados.',
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
