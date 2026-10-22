import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';

/// `IconButton` compacto com formato circular GARANTIDO para hover/focus/
/// splash/pressed — substitui o padrão `IconButton(visualDensity: compact,
/// ...)` repetido em vários pontos do app (toolbar de ordenação, paginação,
/// sidebar, cabeçalho de página, diálogos), cujo destaque dependia do
/// `shape` padrão do Material 3 resolvido a partir da densidade visual
/// efetiva — a própria documentação do Flutter alerta que
/// `IconButton.visualDensity = VisualDensity.compact` pode produzir um
/// destaque com cantos retos em vez do círculo esperado. Em vez de deixar
/// isso implícito/dependente de versão, o `shape` e a área de toque aqui
/// são explícitos.
///
/// Área de toque 32x32 no desktop/tablet — mesma convenção já usada em
/// `PaginationControls._PageNumberButton`, pequena o bastante para não
/// parecer um retângulo gigante ao lado de um ícone pequeno, mas ainda
/// confortável para clique com mouse. No mobile ([ScreenSize.mobile]) a
/// área de toque sobe para 44x44 (mínimo seguro para dedo, "Fase 2 —
/// densidade mobile") SEM aumentar o ícone visual — só a região invisível
/// de toque ao redor dele cresce.
class CompactIconButton extends StatelessWidget {
  const CompactIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize,
    this.color,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// `null` usa o tamanho padrão do `IconButton` — alguns usos passam o
  /// ícone já com `size`/`color` próprios (`Icon(..., size: 18)`), caso em
  /// que este parâmetro fica sem efeito (o `Icon` explícito prevalece).
  final double? iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final mobile = context.screenSize == ScreenSize.mobile;
    final touchSize = mobile ? 44.0 : 32.0;
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      color: color,
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        padding: EdgeInsets.zero,
        minimumSize: Size(touchSize, touchSize),
        tapTargetSize: mobile
            ? MaterialTapTargetSize.padded
            : MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
