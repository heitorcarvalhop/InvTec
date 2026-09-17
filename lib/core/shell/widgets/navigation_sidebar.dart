import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../navigation_items.dart';
import 'nav_tile.dart';

/// Sidebar fixa usada em tablet/desktop (largura de janela >= 600) —
/// PROMPT 9.3: fundo azul-marinho fixo (mesma identidade nos dois temas,
/// ver [AppColors.sidebarBackground]), independente do restante da tela
/// estar clara ou escura.
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
    return Container(
      width: AppSpacing.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border(right: BorderSide(color: AppColors.sidebarBorder)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BrandHeader(),
            Divider(height: 1, color: AppColors.sidebarBorder),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
                  _SignOutTile(onTap: onLogout),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'InvTec',
            style: TextStyle(color: AppColors.sidebarForeground, fontWeight: FontWeight.w700, fontSize: 20),
          ),
          Text('Gestão de Patrimônio', style: TextStyle(color: AppColors.sidebarForegroundMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// "Sair" reaproveita o mesmo visual de hover/foco de [NavTile], mas nunca
/// fica "selecionado" (não é uma rota).
class _SignOutTile extends StatefulWidget {
  const _SignOutTile({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SignOutTile> createState() => _SignOutTileState();
}

class _SignOutTileState extends State<_SignOutTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: _hovering ? AppColors.sidebarSurfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: widget.onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.logout, size: 20, color: AppColors.sidebarForegroundMuted),
                SizedBox(width: 12),
                Text('Sair', style: TextStyle(color: AppColors.sidebarForegroundMuted, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
