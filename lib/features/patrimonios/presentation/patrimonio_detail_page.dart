import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/patrimonio_detalhe.dart';
import 'patrimonio_detalhe_providers.dart';
import 'widgets/patrimonio_edit_dialog.dart';
import 'widgets/patrimonio_status_chip.dart';

class PatrimonioDetailPage extends ConsumerWidget {
  const PatrimonioDetailPage({super.key, required this.id});

  final String id;

  Future<void> _editar(
    BuildContext context,
    WidgetRef ref,
    PatrimonioDetalhe detalhe,
  ) async {
    final sucesso = await showPatrimonioEditDialog(context, detalhe: detalhe);
    if (sucesso == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Patrimônio atualizado com sucesso.')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalheAsync = ref.watch(patrimonioDetalheProvider(id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: detalheAsync.when(
          data: (detalhe) {
            if (detalhe == null) {
              return const Card(
                child: EmptyState(
                  icon: Icons.search_off,
                  message: 'Patrimônio não encontrado.',
                ),
              );
            }
            return _Detalhe(
              detalhe: detalhe,
              onEditar: () => _editar(context, ref, detalhe),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Center(
            child: EmptyState(
              icon: Icons.error_outline,
              message: 'Não foi possível carregar o patrimônio. Tente novamente.',
              actionLabel: 'Tentar novamente',
              onAction: () => ref.invalidate(patrimonioDetalheProvider(id)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Detalhe extends ConsumerWidget {
  const _Detalhe({required this.detalhe, required this.onEditar});

  final PatrimonioDetalhe detalhe;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final patrimonio = detalhe.patrimonio;
    final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
    final canManage =
        perfil == ProfilePerfil.admin ||
        perfil == ProfilePerfil.gestor ||
        perfil == ProfilePerfil.operador;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patrimonio.numeroPatrimonio ?? 'Sem número patrimonial',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  PatrimonioStatusChip(status: patrimonio.status),
                ],
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              children: [
                _DetailField(
                  label: 'Número patrimonial',
                  value: patrimonio.numeroPatrimonio ?? '—',
                ),
                _DetailField(label: 'Tipo', value: detalhe.tipoNome),
                _DetailField(label: 'Marca', value: patrimonio.marca ?? '—'),
                _DetailField(label: 'Modelo', value: patrimonio.modelo ?? '—'),
                _DetailField(
                  label: 'Número de série',
                  value: patrimonio.numeroSerie ?? '—',
                ),
                _DetailField(
                  label: 'Descrição',
                  value: patrimonio.descricao ?? '—',
                ),
                _DetailField(
                  label: 'Observação',
                  value: patrimonio.observacao ?? '—',
                ),
                _DetailField(label: 'Setor atual', value: detalhe.setorNome),
                _DetailField(
                  label: 'Responsável atual',
                  value: patrimonio.responsavelAtual ?? '—',
                ),
                _DetailField(
                  label: 'Data de aquisição',
                  value: patrimonio.dataAquisicao == null
                      ? '—'
                      : _formatarData(patrimonio.dataAquisicao!),
                ),
                _DetailField(
                  label: 'Data de cadastro',
                  value: _formatarData(patrimonio.dataCadastro),
                ),
                if (detalhe.criadoPorNome != null)
                  _DetailField(
                    label: 'Criado por',
                    value: detalhe.criadoPorNome!,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(
                  Icons.history_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'O histórico completo de movimentações será exibido '
                    'aqui na próxima etapa.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

String _formatarData(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year}';
}
