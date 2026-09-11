import 'package:flutter/material.dart';

import '../../features/auth/domain/profile.dart';

class NavigationItem {
  const NavigationItem({
    required this.route,
    required this.label,
    required this.icon,
    this.perfisPermitidos,
  });

  final String route;
  final String label;
  final IconData icon;

  /// `null` = visível para qualquer perfil ativo. Hoje todos os perfis
  /// enxergam os mesmos menus operacionais (ver docs desta etapa) — o campo
  /// existe para quando isso divergir (ex.: administração de usuários,
  /// restrita a ADMIN/GESTOR). Isto é só controle visual: a autorização
  /// real continua em RLS/RPCs no banco.
  final List<ProfilePerfil>? perfisPermitidos;

  bool visivelPara(ProfilePerfil perfil) {
    return perfisPermitidos == null || perfisPermitidos!.contains(perfil);
  }
}

const navigationItems = [
  NavigationItem(
    route: '/dashboard',
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
  ),
  NavigationItem(
    route: '/patrimonios',
    label: 'Patrimônios',
    icon: Icons.inventory_2_outlined,
  ),
  NavigationItem(
    route: '/movimentacoes',
    label: 'Movimentações',
    icon: Icons.swap_horiz_outlined,
  ),
  NavigationItem(
    route: '/setores',
    label: 'Setores',
    icon: Icons.apartment_outlined,
  ),
];

const configuracoesItem = NavigationItem(
  route: '/configuracoes',
  label: 'Configurações',
  icon: Icons.settings_outlined,
);

List<NavigationItem> navigationItemsFor(ProfilePerfil perfil) {
  return navigationItems.where((item) => item.visivelPara(perfil)).toList();
}
