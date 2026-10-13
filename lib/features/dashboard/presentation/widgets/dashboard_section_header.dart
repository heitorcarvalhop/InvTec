import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Título de seção do Dashboard ("Patrimônios por setor", "Movimentações
/// recentes"...) com uma ação opcional alinhada à direita (ex.: "Ver
/// todas"). Mesmo estilo em toda seção, para nunca haver dois pesos de
/// título diferentes na mesma tela.
class DashboardSectionHeader extends StatelessWidget {
  const DashboardSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titulo = Text(title, style: AppTypography.cardTitle(context), overflow: TextOverflow.ellipsis);
    if (trailing == null) return titulo;

    return Row(
      children: [
        Expanded(child: titulo),
        trailing!,
      ],
    );
  }
}
