import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Categoria semântica de um [StatusChip] (PROMPT 9.3) — a cor é só reforço
/// visual, o rótulo em texto é sempre exibido junto (nunca só a cor).
enum AppStatusKind { success, warning, error, info, neutral }

/// Badge em formato de pílula usado para status em toda a aplicação
/// (patrimônio, setor, localização, avisos do importador...) — um único
/// componente compartilhado em vez de cada tela desenhar seu próprio pill
/// com cores/raio/padding ligeiramente diferentes.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.kind, this.icon});

  final String label;
  final AppStatusKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).statusColors;
    final (background, foreground) = switch (kind) {
      AppStatusKind.success => (colors.successBackground, colors.successForeground),
      AppStatusKind.warning => (colors.warningBackground, colors.warningForeground),
      AppStatusKind.error => (colors.errorBackground, colors.errorForeground),
      AppStatusKind.info => (colors.infoBackground, colors.infoForeground),
      AppStatusKind.neutral => (colors.neutralBackground, colors.neutralForeground),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
