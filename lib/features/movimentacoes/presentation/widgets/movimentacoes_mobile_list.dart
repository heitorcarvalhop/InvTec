import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/movimentacao.dart';
import '../../domain/movimentacao_listagem_item.dart';
import 'movimentacao_tipo_visual.dart';

class MovimentacoesMobileList extends StatelessWidget {
  const MovimentacoesMobileList({super.key, required this.itens, required this.onVisualizar});

  final List<MovimentacaoListagemItem> itens;
  final ValueChanged<MovimentacaoListagemItem> onVisualizar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in itens)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _MovimentacaoCard(item: item, onTap: () => onVisualizar(item)),
          ),
      ],
    );
  }
}

class _MovimentacaoCard extends StatelessWidget {
  const _MovimentacaoCard({required this.item, required this.onTap});

  final MovimentacaoListagemItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = visualDoTipoMovimentacao(item.tipo);

    return Card(
      child: InkWell(
        onTap: onTap,
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
                        Text(
                          item.patrimonioNumero ?? '—',
                          style: AppTypography.cardTitle(context),
                        ),
                        if (item.patrimonioTipoNome != null)
                          Text(item.patrimonioTipoNome!, style: AppTypography.auxiliary(context)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusChip(label: item.tipo.label, kind: kind, icon: icon),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${item.setorOrigemNome ?? '—'} → ${item.setorDestinoNome ?? '—'}',
                style: AppTypography.body(context),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  if (item.responsavelExibido != null)
                    _InfoChip(icon: Icons.person_outline, texto: item.responsavelExibido!),
                  _InfoChip(icon: Icons.schedule_outlined, texto: _formatarDataHora(item.dataMovimentacao)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onTap, child: const Text('Ver detalhes')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(texto, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}';
}
