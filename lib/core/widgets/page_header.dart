import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Cabeçalho padrão de página: título + subtítulo + ações à direita (que
/// quebram para baixo do título em telas estreitas). Usado em toda página
/// de listagem/gestão para nunca haver dois estilos de cabeçalho
/// diferentes na aplicação.
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

    // Nunca um `Row` aqui: `botoes` (um `Wrap`) não é flexível, então um
    // `Row` lhe daria largura natural irrestrita e espremeria o
    // `Expanded(child: titulo)` em telas estreitas. Um `Wrap` nunca esmaga
    // um item abaixo do tamanho natural: quando não cabem lado a lado, os
    // botões descem para uma nova linha inteira. `SizedBox(width:
    // double.infinity)` é necessário porque um `Wrap` sem largura própria
    // encolhe para o conteúdo, o que quebraria `WrapAlignment.spaceBetween`.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        runSpacing: AppSpacing.md,
        children: [titulo, botoes],
      ),
    );
  }
}
