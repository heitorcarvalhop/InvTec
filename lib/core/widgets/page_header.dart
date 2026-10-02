import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'compact_icon_button.dart';

/// Cabeçalho padrão de página: botão de voltar opcional + título + subtítulo
/// + ações à direita (que quebram para baixo do título em telas estreitas).
/// Usado em toda página de listagem/gestão/página filha para nunca haver
/// dois estilos de cabeçalho diferentes na aplicação.
class InvTecPageHeader extends StatelessWidget {
  const InvTecPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.compact = false,
    this.onBack,
    this.backLabel = 'Voltar',
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Telas estreitas: título e ações empilham em vez de ficar lado a lado.
  final bool compact;

  /// Quando informado, mostra um botão de voltar acima do título — ícone +
  /// texto em telas largas, só ícone com tooltip em telas estreitas. Páginas
  /// principais (navegáveis pela sidebar) nunca devem passar este callback.
  final VoidCallback? onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onBack != null) ...[
          _BackButton(onBack: onBack!, label: backLabel),
          const SizedBox(height: AppSpacing.xs),
        ],
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

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onBack, required this.label});

  final VoidCallback onBack;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (context.screenSize == ScreenSize.mobile) {
      return Align(
        alignment: Alignment.centerLeft,
        child: CompactIconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: label,
          onPressed: onBack,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
