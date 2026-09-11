import 'package:flutter/material.dart';

import '../navigation_items.dart';

/// Item de navegação compartilhado entre a sidebar (desktop/tablet) e o
/// drawer (mobile), para não duplicar o estilo de seleção em dois lugares.
class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      selected: selected,
      selectedTileColor: colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        item.icon,
        color: selected ? colorScheme.onSecondaryContainer : null,
      ),
      title: Text(
        item.label,
        style: TextStyle(
          color: selected ? colorScheme.onSecondaryContainer : null,
          fontWeight: selected ? FontWeight.w600 : null,
        ),
      ),
      onTap: onTap,
    );
  }
}
