import 'package:flutter/material.dart';

import '../../../features/auth/domain/profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../navigation_items.dart';
import 'nav_tile.dart';
import 'user_profile_header.dart';

/// Drawer usado no mobile (largura de janela < 600) — a sidebar fixa do
/// desktop não cabe numa tela pequena. Mesma identidade visual da sidebar
/// (fundo azul-marinho fixo — PROMPT 9.3), para o menu não parecer um
/// componente diferente ao trocar de tamanho de janela.
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
      backgroundColor: AppColors.sidebarBackground,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: UserProfileHeader(profile: profile, onDarkSurface: true),
              ),
            ),
            Divider(height: 1, color: AppColors.sidebarBorder),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                children: [
                  for (final item in items)
                    NavTile(item: item, selected: item.route == currentRoute, onTap: () => onNavigate(item.route)),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.sidebarBorder),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
              child: Column(
                children: [
                  NavTile(
                    item: configuracoesItem,
                    selected: configuracoesItem.route == currentRoute,
                    onTap: () => onNavigate(configuracoesItem.route),
                  ),
                  ListTile(
                    iconColor: AppColors.sidebarForegroundMuted,
                    textColor: AppColors.sidebarForegroundMuted,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
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
