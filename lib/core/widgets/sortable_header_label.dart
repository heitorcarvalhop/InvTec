import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Estado visual de um cabeçalho ordenável — nunca um terceiro valor de
/// direção: "nenhuma seta" já significa "esta coluna não está ordenando
/// agora" (ver `proximoEstadoDeOrdenacao`).
enum SortIndicatorState { none, ascending, descending }

/// Rótulo de cabeçalho clicável, com seta de direção quando a coluna está
/// ordenando — usado tanto em Patrimônios quanto em Movimentações, para as
/// duas telas nunca terem uma UX de ordenação diferente. Nunca depende só da
/// seta: o estado também é anunciado via [Semantics]/[Tooltip] (acessível
/// por leitor de tela e teclado).
class SortableHeaderLabel extends StatelessWidget {
  const SortableHeaderLabel({super.key, required this.label, required this.state, required this.onTap});

  final String label;
  final SortIndicatorState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.label(context);
    final icon = switch (state) {
      SortIndicatorState.ascending => Icons.arrow_upward,
      SortIndicatorState.descending => Icons.arrow_downward,
      SortIndicatorState.none => null,
    };
    final descricao = switch (state) {
      SortIndicatorState.ascending => '$label, ordem crescente',
      SortIndicatorState.descending => '$label, ordem decrescente',
      SortIndicatorState.none => 'Ordenar por $label',
    };

    return Semantics(
      button: true,
      label: descricao,
      child: Tooltip(
        message: descricao,
        child: InkWell(
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, style: style, overflow: TextOverflow.ellipsis)),
              if (icon != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(icon, size: 14, color: style?.color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
