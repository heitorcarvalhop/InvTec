import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/patrimonio_detalhe.dart';
import 'patrimonio_status_chip.dart';

class PatrimonioMobileList extends StatelessWidget {
  const PatrimonioMobileList({
    super.key,
    required this.itens,
    required this.onTap,
  });

  final List<PatrimonioDetalhe> itens;
  final ValueChanged<PatrimonioDetalhe> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in itens)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _PatrimonioCard(detalhe: item, onTap: () => onTap(item)),
          ),
      ],
    );
  }
}

class _PatrimonioCard extends StatelessWidget {
  const _PatrimonioCard({required this.detalhe, required this.onTap});

  final PatrimonioDetalhe detalhe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patrimonio = detalhe.patrimonio;
    final equipamento = [
      patrimonio.marca,
      patrimonio.modelo,
    ].where((v) => v != null && v.isNotEmpty).join(' ');

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
                          patrimonio.numeroPatrimonio ?? 'Sem número',
                          style: theme.textTheme.titleMedium,
                        ),
                        if (equipamento.isNotEmpty)
                          Text(equipamento, style: theme.textTheme.bodyMedium),
                        Text(
                          detalhe.tipoNome,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PatrimonioStatusChip(status: patrimonio.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  _InfoChip(icon: Icons.apartment_outlined, texto: detalhe.setorNome),
                  if (patrimonio.responsavelAtual != null)
                    _InfoChip(
                      icon: Icons.person_outline,
                      texto: patrimonio.responsavelAtual!,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onTap,
                  child: const Text('Ver detalhes'),
                ),
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
        Text(
          texto,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
