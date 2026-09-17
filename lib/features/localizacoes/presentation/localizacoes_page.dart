import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../setores/domain/setor.dart';
import '../domain/localizacao.dart';
import 'localizacoes_controller.dart';
import 'widgets/localizacao_form_dialog.dart';

/// Tela de gestão das localizações de UMA gerência (`/setores/:setorId/
/// localizacoes`) — seção 24. ADMIN/GESTOR podem criar/editar/desativar;
/// OPERADOR/CONSULTA só leitura. Nunca DELETE.
class LocalizacoesPage extends ConsumerStatefulWidget {
  const LocalizacoesPage({super.key, required this.setor});

  final Setor setor;

  @override
  ConsumerState<LocalizacoesPage> createState() => _LocalizacoesPageState();
}

class _LocalizacoesPageState extends ConsumerState<LocalizacoesPage> {
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _nova() async {
    final sucesso = await showLocalizacaoFormDialog(context, setorId: widget.setor.id);
    if (sucesso == true) _showMessage('Localização cadastrada com sucesso.');
  }

  Future<void> _editar(Localizacao localizacao) async {
    final sucesso = await showLocalizacaoFormDialog(
      context,
      setorId: widget.setor.id,
      localizacao: localizacao,
    );
    if (sucesso == true) _showMessage('Localização atualizada com sucesso.');
  }

  Future<void> _alternarAtivo(Localizacao localizacao) async {
    if (localizacao.ativo) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Desativar localização?'),
          content: Text(
            'A localização "${localizacao.nome}" continuará aparecendo no '
            'histórico, mas não poderá ser escolhida para novos '
            'cadastros/movimentações.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Desativar'),
            ),
          ],
        ),
      );
      if (confirmou != true) return;
    }

    try {
      await ref
          .read(localizacoesControllerProvider(widget.setor.id).notifier)
          .alterarAtivo(id: localizacao.id, ativo: !localizacao.ativo);
      _showMessage(localizacao.ativo ? 'Localização desativada.' : 'Localização reativada.');
    } on AppException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Erro inesperado. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
    final canManage = perfil == ProfilePerfil.admin || perfil == ProfilePerfil.gestor;
    final localizacoesAsync = ref.watch(localizacoesControllerProvider(widget.setor.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InvTecPageHeader(
              title: 'Localizações de ${widget.setor.nome}',
              subtitle:
                  'Localizações pertencem sempre a esta gerência — a gerência '
                  'de uma localização não pode ser alterada depois de criada.',
              actions: canManage
                  ? [
                      FilledButton.icon(
                        onPressed: _nova,
                        icon: const Icon(Icons.add),
                        label: const Text('Nova localização'),
                      ),
                    ]
                  : const [],
            ),
            const SizedBox(height: AppSpacing.lg),
            localizacoesAsync.when(
              data: (localizacoes) {
                if (localizacoes.isEmpty) {
                  return Card(
                    child: EmptyState(
                      icon: Icons.place_outlined,
                      message:
                          'Esta gerência não possui localizações cadastradas.\n'
                          'Localizações são opcionais para o patrimônio.',
                      actionLabel: canManage ? 'Cadastrar localização' : null,
                      onAction: canManage ? _nova : null,
                    ),
                  );
                }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < localizacoes.length; i++) ...[
                        _LocalizacaoTile(
                          localizacao: localizacoes[i],
                          canManage: canManage,
                          onEdit: () => _editar(localizacoes[i]),
                          onToggleAtivo: () => _alternarAtivo(localizacoes[i]),
                        ),
                        if (i < localizacoes.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Center(
                child: EmptyState(
                  icon: Icons.error_outline,
                  message: 'Não foi possível acessar as localizações. Tente novamente.',
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.read(localizacoesControllerProvider(widget.setor.id).notifier).recarregar(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalizacaoTile extends StatelessWidget {
  const _LocalizacaoTile({
    required this.localizacao,
    required this.canManage,
    required this.onEdit,
    required this.onToggleAtivo,
  });

  final Localizacao localizacao;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onToggleAtivo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          if (localizacao.sigla != null && localizacao.sigla!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Text(
                localizacao.sigla!,
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          Expanded(child: Text(localizacao.nome, overflow: TextOverflow.ellipsis)),
          StatusChip(
            label: localizacao.ativo ? 'Ativa' : 'Inativa',
            kind: localizacao.ativo ? AppStatusKind.success : AppStatusKind.neutral,
          ),
          if (canManage) ...[
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: localizacao.ativo ? 'Desativar' : 'Reativar',
              icon: Icon(localizacao.ativo ? Icons.block_outlined : Icons.check_circle_outline),
              onPressed: onToggleAtivo,
            ),
          ],
        ],
      ),
    );
  }
}
