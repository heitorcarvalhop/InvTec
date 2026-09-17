import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'status_chip.dart';

/// Card de métrica (ícone + valor + descrição) usado no Dashboard —
/// PROMPT 9.3. [kind] tinge só o ícone com uma cor contextual discreta
/// (nunca o card inteiro), coerente com o resto dos status da aplicação.
class InvTecStatCard extends StatelessWidget {
  const InvTecStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.kind = AppStatusKind.info,
  });

  final String label;
  final int value;
  final IconData icon;
  final AppStatusKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).statusColors;
    final tint = switch (kind) {
      AppStatusKind.success => colors.successForeground,
      AppStatusKind.warning => colors.warningForeground,
      AppStatusKind.error => colors.errorForeground,
      AppStatusKind.info => colors.infoForeground,
      AppStatusKind.neutral => colors.neutralForeground,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tint),
            const SizedBox(height: AppSpacing.sm),
            Text('$value', style: AppTypography.metric(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: AppTypography.auxiliary(context)),
          ],
        ),
      ),
    );
  }
}
