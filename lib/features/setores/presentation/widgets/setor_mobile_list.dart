import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/setor.dart';
import 'setor_status_chip.dart';

class SetorMobileList extends StatelessWidget {
  const SetorMobileList({
    super.key,
    required this.setores,
    required this.canManage,
    required this.onEdit,
    required this.onToggleAtivo,
  });

  final List<Setor> setores;
  final bool canManage;
  final ValueChanged<Setor> onEdit;
  final ValueChanged<Setor> onToggleAtivo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final setor in setores)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SetorCard(
              setor: setor,
              canManage: canManage,
              onEdit: () => onEdit(setor),
              onToggleAtivo: () => onToggleAtivo(setor),
            ),
          ),
      ],
    );
  }
}

class _SetorCard extends StatelessWidget {
  const _SetorCard({
    required this.setor,
    required this.canManage,
    required this.onEdit,
    required this.onToggleAtivo,
  });

  final Setor setor;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onToggleAtivo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final temSigla = setor.sigla != null && setor.sigla!.isNotEmpty;
    final temDescricao = setor.descricao != null && setor.descricao!.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (temSigla)
                        Text(
                          setor.sigla!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Text(setor.nome, style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SetorStatusChip(ativo: setor.ativo),
              ],
            ),
            if (temDescricao) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(setor.descricao!, style: theme.textTheme.bodyMedium),
            ],
            if (canManage) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                  TextButton.icon(
                    onPressed: onToggleAtivo,
                    icon: Icon(
                      setor.ativo
                          ? Icons.block_outlined
                          : Icons.check_circle_outline,
                    ),
                    label: Text(setor.ativo ? 'Desativar' : 'Reativar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
