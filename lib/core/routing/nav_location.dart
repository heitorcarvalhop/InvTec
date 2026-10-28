import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Abas da navegação inferior do celular. Cada uma corresponde a UMA rota
/// exata — nenhuma rota interna "herda" uma aba por falta de correspondência.
enum NavTab {
  inicio('/dashboard', 'Início'),
  patrimonios('/patrimonios', 'Patrimônios'),
  escanear('/patrimonios/escanear', 'Escanear'),
  movimentacoes('/movimentacoes', 'Movimentações');

  const NavTab(this.rota, this.rotulo);
  final String rota;
  final String rotulo;
}

/// Única fonte de verdade sobre "onde o usuário está": barra inferior,
/// Drawer, cabeçalho compacto e botão voltar derivam todos daqui.
class NavLocation {
  NavLocation._();

  static const _configuracoes = '/configuracoes';
  static const _admin = '/administracao/usuarios';
  // Setores saiu da barra inferior, mas segue sendo tela principal do menu.
  static const _setores = '/setores';

  /// Caminho real em exibição, incluindo páginas empilhadas com `push`
  /// (o `state` do `ShellRoute` não enxerga essas pushes — origem do bug em
  /// que o scanner/"Novo patrimônio" ainda marcavam "Início").
  ///
  /// `configuration.uri` NÃO reflete uma página empilhada: fica na rota-base.
  /// O último `RouteMatch` (inclusive o imperativo, de `push`) carrega a
  /// localização real.
  static String pathAtual(GoRouter router) {
    final config = router.routerDelegate.currentConfiguration;
    if (config.matches.isEmpty) return normalizar(config.uri.path);
    return normalizar(Uri.parse(config.last.matchedLocation).path);
  }

  static String normalizar(String path) => path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;

  /// Aba da barra inferior para [path]; `null` para qualquer outra rota.
  static NavTab? abaDe(String path) {
    final p = normalizar(path);
    for (final aba in NavTab.values) {
      if (aba.rota == p) return aba;
    }
    return null;
  }

  /// Raiz de uma aba — é onde a barra inferior aparece.
  static bool ehRaizDeAba(String path) => abaDe(path) != null;

  /// Destino do Drawer sem aba (Configurações, Administração): tela
  /// principal, abre o menu em vez de "voltar".
  static bool ehNivelSuperior(String path) {
    final p = normalizar(path);
    return ehRaizDeAba(p) ||
        p == _setores ||
        p == _configuracoes ||
        p == _admin;
  }

  /// Rota "pai" lógica, usada quando não há nada empilhado para voltar.
  static String paiDe(String path) {
    final p = normalizar(path);
    if (ehNivelSuperior(p)) return '/dashboard';
    if (p.startsWith('/patrimonios/')) return '/patrimonios';
    if (p.startsWith('/movimentacoes/')) return '/movimentacoes';
    if (p.startsWith('/setores/')) return '/setores';
    if (p.startsWith('$_admin/')) return _admin;
    return '/dashboard';
  }

  /// Título do cabeçalho compacto do celular.
  static String tituloDe(String path) {
    final p = normalizar(path);
    switch (p) {
      case '/dashboard':
        return 'InvTec';
      case '/patrimonios':
        return 'Patrimônios';
      case '/patrimonios/escanear':
        return 'Escanear patrimônio';
      case '/patrimonios/novo':
        return 'Novo patrimônio';
      case '/patrimonios/importar':
        return 'Importar planilha';
      case '/patrimonios/inventario-rapido':
        return 'Inventário rápido';
      case '/patrimonios/retificar-unidade':
        return 'Retificar unidade';
      case '/movimentacoes':
        return 'Movimentações';
      case '/setores':
        return 'Setores';
      case _configuracoes:
        return 'Configurações';
      case _admin:
        return 'Administração';
    }
    if (p.startsWith('/patrimonios/')) return 'Detalhes do patrimônio';
    if (p.startsWith('/movimentacoes/')) return 'Movimentação';
    if (p.endsWith('/localizacoes')) return 'Localizações';
    if (p.startsWith('$_admin/')) return 'Usuário';
    return 'InvTec';
  }
}

/// Avisa às páginas que o cabeçalho do shell (celular) já mostra o título e
/// o "voltar" — [InvTecPageHeader] omite o que seria duplicado.
class ShellHeaderScope extends InheritedWidget {
  const ShellHeaderScope({
    super.key,
    required this.titulo,
    required super.child,
  });

  final String titulo;

  static ShellHeaderScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellHeaderScope>();

  @override
  bool updateShouldNotify(ShellHeaderScope old) => old.titulo != titulo;
}

extension NavegacaoSegura on BuildContext {
  /// `push` que ignora o toque quando [rota] já é a tela em exibição —
  /// evita empilhar duas vezes a mesma tela (toques repetidos em ação
  /// rápida, notificação ou botão).
  Future<T?> pushUnico<T extends Object?>(String rota) {
    final router = GoRouter.of(this);
    final destino = Uri.parse(rota).path;
    if (NavLocation.pathAtual(router) == destino) return Future<T?>.value();
    return push<T>(rota);
  }
}
