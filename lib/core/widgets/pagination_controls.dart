import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// "Anterior / Página X de Y / Próxima" — genérico o bastante para
/// qualquer listagem paginada do InvTec.
class PaginationControls extends StatelessWidget {
  const PaginationControls({
    super.key,
    required this.paginaAtual,
    required this.totalPaginas,
    required this.onChanged,
  });

  /// 0-based.
  final int paginaAtual;
  final int totalPaginas;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final podeVoltar = paginaAtual > 0;
    final podeAvancar = paginaAtual < totalPaginas - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: podeVoltar ? () => onChanged(paginaAtual - 1) : null,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Anterior'),
        ),
        const SizedBox(width: AppSpacing.md),
        Text('Página ${paginaAtual + 1} de $totalPaginas'),
        const SizedBox(width: AppSpacing.md),
        TextButton.icon(
          onPressed: podeAvancar ? () => onChanged(paginaAtual + 1) : null,
          icon: const Icon(Icons.chevron_right),
          label: const Text('Próxima'),
        ),
      ],
    );
  }
}
