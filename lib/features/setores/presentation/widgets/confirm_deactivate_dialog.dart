import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/setor.dart';

/// Confirmação antes de desativar — a única ação desta tela destrutiva o
/// bastante para pedir confirmação (editar/reativar não pedem).
Future<bool> confirmarDesativacao(BuildContext context, Setor setor) async {
  final colorScheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 22),
          const SizedBox(width: AppSpacing.sm),
          const Flexible(child: Text('Desativar setor?')),
        ],
      ),
      content: Text(
        'O setor "${setor.nome}" continuará aparecendo no histórico, mas '
        'não poderá ser utilizado como destino de novas movimentações.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        // Mesmo tratamento "danger" do diálogo equivalente em Localizações —
        // colorScheme.error em vez do azul primário padrão, para uma ação
        // destrutiva nunca parecer visualmente idêntica a uma confirmação
        // comum.
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Desativar'),
        ),
      ],
    ),
  );
  return result ?? false;
}
