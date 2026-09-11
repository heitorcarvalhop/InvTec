import 'package:flutter/material.dart';

import '../../../features/auth/domain/profile.dart';
import '../../theme/app_spacing.dart';
import '../navigation_items.dart';
import 'nav_tile.dart';
import 'user_profile_header.dart';

/// Drawer usado no mobile (largura de janela < 600) — a sidebar fixa do
/// desktop não cabe numa tela pequena.
class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({
    super.key,
    required this.profile,
    required this.currentRoute,
    required this.items,
    required this.onNavigate,
    required this.onLogout,
  });

  final Profile profile;
  final String currentRoute;
  final List<NavigationItem> items;
  final ValueChanged<String> onNavigate;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: UserProfileHeader(profile: profile),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
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
    );
  }
}
