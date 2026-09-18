import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'status_chip.dart';

/// Card de métrica (ícone + valor + descrição) usado no Dashboard —
/// PROMPT 9.3. [kind] tinge só o pequeno badge do ícone com uma cor
/// contextual discreta (PROMPT 9.3.3: nunca o card inteiro), coerente com
/// o resto dos status da aplicação.
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
    final statusColors = Theme.of(context).statusColors;
    final (tintBackground, tintForeground) = switch (kind) {
      AppStatusKind.success => (statusColors.successBackground, statusColors.successForeground),
      AppStatusKind.warning => (statusColors.warningBackground, statusColors.warningForeground),
      AppStatusKind.error => (statusColors.errorBackground, statusColors.errorForeground),
      AppStatusKind.info => (statusColors.infoBackground, statusColors.infoForeground),
      AppStatusKind.neutral => (statusColors.neutralBackground, statusColors.neutralForeground),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tintBackground,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: tintForeground),
            ),
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
