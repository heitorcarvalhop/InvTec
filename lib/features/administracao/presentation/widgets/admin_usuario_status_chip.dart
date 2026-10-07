import 'package:flutter/material.dart';

import '../../../../core/widgets/status_chip.dart';
import '../../../auth/domain/profile.dart';

/// Badge de `access_status` — mapeia cada [ProfileAccessStatus] para a
/// categoria semântica de [StatusChip] mais próxima: ativo = sucesso,
/// pendente = atenção (decisão ainda não tomada), rejeitado = neutro
/// (decisão tomada, não é um estado de erro do sistema em si), bloqueado =
/// erro (acesso ativamente impedido).
class AdminUsuarioStatusChip extends StatelessWidget {
  const AdminUsuarioStatusChip({super.key, required this.status});

  final ProfileAccessStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, kind) = switch (status) {
      ProfileAccessStatus.pending => ('Pendente', AppStatusKind.warning),
      ProfileAccessStatus.active => ('Ativo', AppStatusKind.success),
      ProfileAccessStatus.rejected => ('Rejeitado', AppStatusKind.neutral),
      ProfileAccessStatus.blocked => ('Bloqueado', AppStatusKind.error),
    };
    return StatusChip(label: label, kind: kind);
  }
}
