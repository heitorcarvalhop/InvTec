import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../navigation_items.dart';
import 'nav_tile.dart';

/// Sidebar fixa usada em tablet/desktop (largura de janela >= 600).
class NavigationSidebar extends StatelessWidget {
  const NavigationSidebar({
    super.key,
    required this.currentRoute,
    required this.items,
    required this.onNavigate,
    required this.onLogout,
  });

  final String currentRoute;
  final List<NavigationItem> items;
  final ValueChanged<String> onNavigate;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: AppSpacing.sidebarWidth,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      // Material (não só a cor no Container) para que o ink splash dos
      // ListTiles pinte sobre este ancestral, e não fique escondido atrás
      // dele — ver aviso do Flutter sobre DecoratedBox + ListTile.
      child: Material(
        color: colorScheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  children: [
                    for (final item in items)
                      NavTile(
                        item: item,
                        selected: item.route == currentRoute,
                        onTap: () => onNavigate(item.route),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    NavTile(
                      item: configuracoesItem,
                      selected: configuracoesItem.route == currentRoute,
                      onTap: () => onNavigate(configuracoesItem.route),
                    ),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: const Icon(Icons.logout),
                      title: const Text('Sair'),
                      onTap: onLogout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
