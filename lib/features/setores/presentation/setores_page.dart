import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/setor.dart';
import 'setores_controller.dart';
import 'widgets/confirm_deactivate_dialog.dart';
import 'widgets/setor_desktop_table.dart';
import 'widgets/setor_form_dialog.dart';
import 'widgets/setor_mobile_list.dart';

class SetoresPage extends ConsumerStatefulWidget {
  const SetoresPage({super.key});

  @override
  ConsumerState<SetoresPage> createState() => _SetoresPageState();
}

class _SetoresPageState extends ConsumerState<SetoresPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Só para atualizar o texto do estado vazio (busca x cadastro vazio);
    // a consulta em si é disparada com debounce pelo controller.
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _verLocalizacoes(Setor setor) {
    context.push('/setores/${setor.id}/localizacoes', extra: setor);
  }

  Future<void> _novoSetor() async {
    final sucesso = await showSetorFormDialog(context);
    if (sucesso == true) _showMessage('Setor cadastrado com sucesso.');
  }

  Future<void> _editarSetor(Setor setor) async {
    final sucesso = await showSetorFormDialog(context, setor: setor);
    if (sucesso == true) _showMessage('Setor atualizado com sucesso.');
  }

  Future<void> _alternarAtivo(Setor setor) async {
    if (setor.ativo) {
      final confirmou = await confirmarDesativacao(context, setor);
      if (!confirmou) return;
    }

    try {
      await ref
          .read(setoresControllerProvider.notifier)
          .alterarAtivo(id: setor.id, ativo: !setor.ativo);
      _showMessage(setor.ativo ? 'Setor desativado.' : 'Setor reativado.');
    } on AppException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Erro inesperado. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
    final canManage =
        perfil == ProfilePerfil.admin || perfil == ProfilePerfil.gestor;
    final setoresAsync = ref.watch(setoresControllerProvider);
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
              title: 'Setores',
              subtitle: 'Gerencie as localizações utilizadas pelos patrimônios.',
              compact: context.screenSize == ScreenSize.mobile,
              actions: canManage
                  ? [
                      FilledButton.icon(
                        onPressed: _novoSetor,
                        icon: const Icon(Icons.add),
                        label: const Text('Novo setor'),
                      ),
                    ]
                  : const [],
            ),
            const SizedBox(height: AppSpacing.md),
            // Mesmo tratamento de painel da busca em Patrimônios (PROMPT
            // 9.3.3, seção 8) — consistência visual entre as duas telas.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _SearchField(
                  controller: _searchController,
                  onChanged: (value) =>
                      ref.read(setoresControllerProvider.notifier).buscar(value),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            setoresAsync.when(
              data: (setores) {
                if (setores.isEmpty) {
                  return _EmptyList(
                    termoBusca: termoBusca,
                    canManage: canManage,
                    onNovoSetor: _novoSetor,
                  );
                }
                return context.screenSize == ScreenSize.mobile
                    ? SetorMobileList(
                        setores: setores,
                        canManage: canManage,
                        onEdit: _editarSetor,
                        onToggleAtivo: _alternarAtivo,
                        onLocalizacoes: _verLocalizacoes,
                      )
                    : SetorDesktopTable(
                        setores: setores,
                        canManage: canManage,
                        onEdit: _editarSetor,
                        onToggleAtivo: _alternarAtivo,
                        onLocalizacoes: _verLocalizacoes,
                      );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Center(
                child: EmptyState(
                  icon: Icons.error_outline,
                  message: 'Não foi possível acessar os setores. Tente novamente.',
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.read(setoresControllerProvider.notifier).recarregar(),
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
        hintText: 'Buscar por nome ou sigla',
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
    required this.termoBusca,
    required this.canManage,
    required this.onNovoSetor,
  });

  final String termoBusca;
  final bool canManage;
  final VoidCallback onNovoSetor;

  @override
  Widget build(BuildContext context) {
    if (termoBusca.isNotEmpty) {
      return Card(
        child: EmptyState(
          icon: Icons.search_off,
          message: 'Nenhum setor encontrado para "$termoBusca".',
        ),
      );
    }

    return Card(
      child: EmptyState(
        icon: Icons.apartment_outlined,
        message:
            'Nenhum setor cadastrado.\nCadastre o primeiro setor para '
            'começar a organizar os patrimônios.',
        actionLabel: canManage ? 'Cadastrar setor' : null,
        onAction: canManage ? onNovoSetor : null,
      ),
    );
  }
}
