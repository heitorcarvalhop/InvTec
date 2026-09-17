import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/patrimonio_detalhe.dart';
import '../domain/patrimonio_search_field.dart';
import 'patrimonios_controller.dart';
import 'patrimonios_filtro.dart';
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

  /// Seção 9: limpar filtros limpa texto + campo de busca (-> Tudo) + Tipo +
  /// Status + Setor — nunca só o lado do controller, senão o texto digitado
  /// e o seletor ficariam visualmente "presos" no valor antigo.
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
            InvTecPageHeader(
              title: 'Patrimônios',
              subtitle: 'Consulte e gerencie os equipamentos cadastrados no InvTec.',
              compact: context.screenSize == ScreenSize.mobile,
              actions: canManage
                  ? [
                      OutlinedButton.icon(
                        onPressed: _importarPlanilha,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Importar planilha'),
                      ),
                      FilledButton.icon(
                        onPressed: _novoPatrimonio,
                        icon: const Icon(Icons.add),
                        label: const Text('Novo patrimônio'),
                      ),
                    ]
                  : const [],
            ),
            const SizedBox(height: AppSpacing.md),
            _SearchBar(
              controller: _searchController,
              campoBusca: _campoBusca,
              onCampoBuscaChanged: _alterarCampoBusca,
              onChanged: (value) => ref
                  .read(patrimoniosControllerProvider.notifier)
                  .buscar(value),
            ),
            const SizedBox(height: AppSpacing.md),
            stateAsync.maybeWhen(
              data: (state) => PatrimonioFilters(
                filtro: state.filtro,
                onLimparFiltros: _limparFiltros,
              ),
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
                    termoBusca: termoBusca,
                    correspondenciasPorNumeroSerie:
                        state.resultado.correspondenciasPorNumeroSerie.length,
                    onVerCorrespondenciaSerie: () =>
                        _alterarCampoBusca(PatrimonioSearchField.numeroSerie),
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

/// Barra de busca (PROMPT 9.1, seção 2): seletor de campo + texto livre,
/// lado a lado — `[ Tudo ▼ ] [ Buscar... ]`. O seletor nunca dispara
/// consulta sozinho pelo `TextField` (que continua com debounce): a
/// mudança de campo é imediata, via [onCampoBuscaChanged].
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.campoBusca,
    required this.onCampoBuscaChanged,
    required this.onChanged,
  });

  final TextEditingController controller;
  final PatrimonioSearchField campoBusca;
  final ValueChanged<PatrimonioSearchField> onCampoBuscaChanged;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<PatrimonioSearchField>(
            initialValue: campoBusca,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Buscar em'),
            items: [
              for (final campo in PatrimonioSearchField.values)
                DropdownMenuItem(value: campo, child: Text(campo.label)),
            ],
            onChanged: (campo) {
              if (campo != null) onCampoBuscaChanged(campo);
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: campoBusca.dica,
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
          ),
        ),
      ],
    );
  }
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

  /// PROMPT 9.1.1: quantidade de patrimônios cujo NÚMERO DE SÉRIE (nunca o
  /// número de patrimônio) coincide com [termoBusca] — só populado quando
  /// não há nenhum patrimônio com esse número exato. Nunca aparece
  /// misturado com a listagem principal, nem é apresentado como se fosse
  /// "o patrimônio pesquisado".
  final int correspondenciasPorNumeroSerie;
  final VoidCallback onVerCorrespondenciaSerie;
  final bool canManage;
  final VoidCallback onNovoPatrimonio;

  @override
  Widget build(BuildContext context) {
    if (temFiltroOuBusca) {
      // Seção 7 (PROMPT 9.1): mensagem específica com o termo digitado,
      // quando houver — nunca uma mensagem genérica que esconda o que foi
      // pesquisado.
      final mensagem = termoBusca.isEmpty
          ? 'Nenhum patrimônio encontrado.'
          : correspondenciasPorNumeroSerie > 0
          // PROMPT 9.1.1: deixa explícito que o termo NÃO é o número de um
          // patrimônio encontrado — nunca silenciosamente mostrar outro
          // patrimônio como se fosse a resposta.
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
