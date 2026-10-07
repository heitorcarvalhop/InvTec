import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Linha de erro inline padrão dos diálogos desta feature — mesmo
/// tratamento visual do `SetorFormDialog` (ícone + texto na cor de erro do
/// tema), reaproveitado aqui para não repetir o mesmo `Row` em cada
/// diálogo de ação administrativa (Aprovar/Rejeitar/Bloquear/...).
Widget buildErroInlineDialog(BuildContext context, String mensagem) {
  final colorScheme = Theme.of(context).colorScheme;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.error_outline, size: 18, color: colorScheme.error),
      const SizedBox(width: AppSpacing.xs),
      Expanded(child: Text(mensagem, style: TextStyle(color: colorScheme.error))),
    ],
  );
}

/// Spinner compacto para o botão de confirmação enquanto uma ação está em
/// andamento — mesmo tamanho usado em `SetorFormDialog`/`LoginPage`.
const Widget dialogButtonSpinner = SizedBox(
  width: 20,
  height: 20,
  child: CircularProgressIndicator(strokeWidth: 2),
);
