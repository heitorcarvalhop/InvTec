import 'package:flutter/material.dart';

/// Chip de filtro ativo — `[Status: Disponível ×]` — usado abaixo da
/// [ListPageToolbar] quando a tela tem filtros aplicados. Fino wrapper sobre
/// `InputChip` só para o rótulo "chip de filtro ativo" não se repetir
/// diferente em cada tela.
class ActiveFilterChip extends StatelessWidget {
  const ActiveFilterChip({super.key, required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(label: Text(label), onDeleted: onRemove);
  }
}
