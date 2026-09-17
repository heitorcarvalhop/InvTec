import 'package:flutter/material.dart';

import '../../../../core/widgets/status_chip.dart';

/// Status amigável (nunca `true`/`false` na tela).
class SetorStatusChip extends StatelessWidget {
  const SetorStatusChip({super.key, required this.ativo});

  final bool ativo;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: ativo ? 'Ativo' : 'Inativo',
      kind: ativo ? AppStatusKind.success : AppStatusKind.neutral,
    );
  }
}
