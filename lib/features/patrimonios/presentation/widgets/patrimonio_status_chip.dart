import 'package:flutter/material.dart';

import '../../../../core/widgets/status_chip.dart';
import '../../domain/patrimonio.dart';

/// Status amigável (nunca o enum técnico na tela). Cor é só reforço visual
/// — o texto é sempre exibido, nunca a única forma de comunicar o status.
class PatrimonioStatusChip extends StatelessWidget {
  const PatrimonioStatusChip({super.key, required this.status});

  final PatrimonioStatus status;

  @override
  Widget build(BuildContext context) {
    final kind = switch (status) {
      PatrimonioStatus.disponivel => AppStatusKind.success,
      PatrimonioStatus.emUso => AppStatusKind.info,
      PatrimonioStatus.emprestado => AppStatusKind.warning,
      PatrimonioStatus.emManutencao => AppStatusKind.warning,
      PatrimonioStatus.baixado => AppStatusKind.neutral,
    };
    return StatusChip(label: status.label, kind: kind);
  }
}
