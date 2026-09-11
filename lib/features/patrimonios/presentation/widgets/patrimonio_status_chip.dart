import 'package:flutter/material.dart';

import '../../domain/patrimonio.dart';

/// Status amigável (nunca o enum técnico na tela). Cor é só reforço visual
/// — o texto é sempre exibido, nunca a única forma de comunicar o status.
class PatrimonioStatusChip extends StatelessWidget {
  const PatrimonioStatusChip({super.key, required this.status});

  final PatrimonioStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      PatrimonioStatus.disponivel => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
      PatrimonioStatus.emUso => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      PatrimonioStatus.emprestado => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
      ),
      PatrimonioStatus.emManutencao => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      PatrimonioStatus.baixado => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}
