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

  group('NavigationItem.ativoPara', () {
    const item = NavigationItem(route: '/patrimonios', label: 'Patrimônios', icon: Icons.abc);

    test('rota exatamente igual é ativa', () {
      expect(item.ativoPara('/patrimonios'), isTrue);
    });

    test('página filha (sub-rota) também marca o item como ativo', () {
      expect(item.ativoPara('/patrimonios/novo'), isTrue);
      expect(item.ativoPara('/patrimonios/importar'), isTrue);
      expect(item.ativoPara('/patrimonios/abc-123'), isTrue);
    });

    test('rota de outro item não é ativa', () {
      expect(item.ativoPara('/setores'), isFalse);
    });

    test('rota que só começa parecido, sem ser filha de verdade, não é ativa', () {
      expect(item.ativoPara('/patrimoniosx'), isFalse);
    });
  });
}
