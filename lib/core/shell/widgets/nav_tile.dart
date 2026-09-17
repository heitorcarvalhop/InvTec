import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../navigation_items.dart';

/// Item de navegação compartilhado entre a sidebar (desktop/tablet) e o
/// drawer (mobile) — PROMPT 9.3: sempre sobre o fundo azul-marinho fixo da
/// navegação ([AppColors.sidebarBackground]), então usa a paleta fixa da
/// sidebar em vez de `Theme.of(context).colorScheme` (que mudaria com o
/// tema claro/escuro e perderia contraste sobre um fundo sempre escuro).
class NavTile extends StatefulWidget {
  const NavTile({super.key, required this.item, required this.selected, required this.onTap});

  final NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<NavTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final background = widget.selected
        ? AppColors.sidebarSelectedBackground
        : (_hovering ? AppColors.sidebarSurfaceHover : Colors.transparent);
    final foreground = widget.selected ? AppColors.sidebarSelectedForeground : AppColors.sidebarForeground;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(widget.item.icon, size: 20, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
