import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Cabeçalho padrão de página: título + subtítulo + ações à direita (que
/// quebram para baixo do título em telas estreitas) — PROMPT 9.3. Usado em
/// toda página de listagem/gestão para nunca haver dois estilos de
/// cabeçalho diferentes na aplicação.
class InvTecPageHeader extends StatelessWidget {
  const InvTecPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Telas estreitas: título e ações empilham em vez de ficar lado a lado.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTypography.pageTitle(context)),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle!, style: AppTypography.pageSubtitle(context)),
        ],
      ],
    );

    if (actions.isEmpty) return titulo;

    final botoes = Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions);

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titulo, const SizedBox(height: AppSpacing.md), botoes],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: titulo), const SizedBox(width: AppSpacing.md), botoes],
    );
  }
}
