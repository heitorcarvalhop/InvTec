import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/shell/navigation_items.dart';
import 'package:invtec/features/auth/domain/profile.dart';

void main() {
  test('hoje todos os perfis ativos veem os mesmos 4 menus operacionais', () {
    for (final perfil in ProfilePerfil.values) {
      final items = navigationItemsFor(perfil);
      expect(items.map((i) => i.route), [
        '/dashboard',
        '/patrimonios',
        '/movimentacoes',
        '/setores',
      ]);
    }
  });

  test('item sem perfisPermitidos é visível para qualquer perfil', () {
    const item = NavigationItem(
      route: '/x',
      label: 'X',
      icon: Icons.abc,
    );
    for (final perfil in ProfilePerfil.values) {
      expect(item.visivelPara(perfil), isTrue);
    }
  });

  test('item com perfisPermitidos só é visível para os perfis listados', () {
    const item = NavigationItem(
      route: '/admin-only',
      label: 'Admin only',
      icon: Icons.abc,
      perfisPermitidos: [ProfilePerfil.admin, ProfilePerfil.gestor],
    );

    expect(item.visivelPara(ProfilePerfil.admin), isTrue);
    expect(item.visivelPara(ProfilePerfil.gestor), isTrue);
    expect(item.visivelPara(ProfilePerfil.operador), isFalse);
    expect(item.visivelPara(ProfilePerfil.consulta), isFalse);
  });
}
