import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/profile.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/notificacoes/presentation/widgets/notification_bell.dart';
import '../config/platform_info.dart';
import '../responsive/breakpoints.dart';
import '../routing/nav_location.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'bottom_nav.dart';
import 'navigation_items.dart';
import 'sidebar_controller.dart';
import 'widgets/app_navigation_drawer.dart';
import 'widgets/navigation_sidebar.dart';
import 'widgets/theme_toggle_button.dart';
import 'widgets/user_profile_header.dart';

/// Shell reutilizável para todas as páginas autenticadas: cuida de
/// navegação (sidebar no desktop/tablet, drawer no mobile), cabeçalho,
/// usuário atual e logout, para as páginas de rota não duplicarem nada
/// disso — ver [lib/core/routing/app_router.dart], que monta este shell
/// via `ShellRoute`.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.currentRoute, required this.child});

  final String currentRoute;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `currentRoute` (do `state` do ShellRoute) só é usado como reserva: ele
    // não enxerga páginas empilhadas com `push` (scanner, "Novo patrimônio"),
    // então a rota real vem do próprio roteador — uma fonte única para a
    // barra inferior, o Drawer, a sidebar e o botão voltar.
    final router = GoRouter.maybeOf(context);
    if (router == null) return _construir(context, ref, currentRoute);
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) =>
          _construir(context, ref, NavLocation.pathAtual(router)),
    );
  }

  Widget _construir(BuildContext context, WidgetRef ref, String currentRoute) {
    final profile = ref.watch(authControllerProvider).value?.profile;

    // Só acontece durante uma janela curta entre logout e o redirect do
    // GoRouter assumir — nunca deixamos o usuário "preso" aqui.
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final items = navigationItemsFor(profile.perfil);

    void onNavigate(String route) {
      if (route != currentRoute) context.go(route);
    }

    void onLogout() => ref.read(authControllerProvider.notifier).signOut();

    // Sino administrativo: só para ADMIN (etapa não estende notificações a
    // outros perfis ainda — nunca renderizado, nem "vazio", para
    // GESTOR/OPERADOR/CONSULTA/PENDING/REJECTED/BLOCKED).
    final mostrarSinoNotificacoes = profile.perfil == ProfilePerfil.admin;

    if (context.screenSize == ScreenSize.mobile) {
      final nivelSuperior = NavLocation.ehNivelSuperior(currentRoute);
      final titulo = NavLocation.tituloDe(currentRoute);
      final router = GoRouter.maybeOf(context);
      final podeSair =
          currentRoute == '/dashboard' && !(router?.canPop() ?? false);

      return ShellHeaderScope(
        titulo: titulo,
        // Voltar do Android (botão/gesto) e seta do cabeçalho seguem a mesma
        // lógica: desempilha o que foi aberto com `push`; sem pilha, sobe
        // para a rota-pai (nunca sai do app fora do Início).
        child: PopScope(
          canPop: podeSair,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (router != null && router.canPop()) {
              router.pop();
            } else {
              context.go(NavLocation.paiDe(currentRoute));
            }
          },
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 52,
              titleSpacing: nivelSuperior ? null : 0,
              // Internas: seta (mesmo caminho do botão do Android). Nível
              // superior: o Scaffold coloca o botão do Drawer sozinho.
              automaticallyImplyLeading: nivelSuperior,
              leading: nivelSuperior
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Voltar',
                      onPressed: () => router?.routerDelegate.popRoute(),
                    ),
              title: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: nivelSuperior
                  ? [
                      if (mostrarSinoNotificacoes) const NotificationBell(),
                      const ThemeToggleButton(compact: true),
                      const SizedBox(width: AppSpacing.sm),
                    ]
                  : null,
            ),
            drawer: AppNavigationDrawer(
              profile: profile,
              currentRoute: currentRoute,
              items: items,
              onNavigate: (route) {
                Navigator.of(context).pop();
                onNavigate(route);
              },
              onLogout: () {
                Navigator.of(context).pop();
                onLogout();
              },
            ),
            body: child,
            bottomNavigationBar: _MobileBottomBar(
              currentRoute: currentRoute,
              podeEscanear: ref.watch(isAndroidProvider),
              onNavigate: onNavigate,
            ),
          ),
        ),
      );
    }

    // Preferência explícita do usuário (persistida); sem ela, tablet
    // começa recolhida (espaço é mais escasso) e desktop começa expandida —
    // e esse padrão automático nunca é gravado, só calculado aqui.
    final preferenciaSalva = ref.watch(sidebarControllerProvider).value;
    final sidebarRecolhida =
        preferenciaSalva ?? (context.screenSize == ScreenSize.tablet);

    void onToggleSidebar() {
      ref.read(sidebarControllerProvider.notifier).definir(!sidebarRecolhida);
    }

    // Sem `Scaffold.appBar`: uma AppBar no Scaffold cria uma faixa de
    // largura total acima de tudo, empurrando a sidebar para baixo dela —
    // mas a sidebar precisa ser full-height. Em vez disso, sidebar e
    // conteúdo (com sua própria topbar) ficam lado a lado dentro do `body`.
    return Scaffold(
      body: Row(
        children: [
          NavigationSidebar(
            currentRoute: currentRoute,
            items: items,
            onNavigate: onNavigate,
            onLogout: onLogout,
            collapsed: sidebarRecolhida,
            onToggleCollapse: onToggleSidebar,
          ),
          Expanded(
            child: Column(
              children: [
                _DesktopTopBar(
                  profile: profile,
                  mostrarSinoNotificacoes: mostrarSinoNotificacoes,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Topbar do desktop: só o seletor de tema e o usuário logado, alinhados à
/// direita, sem título de produto (a marca "InvTec" vive só na sidebar).
/// Mesma cor do fundo da página, com uma borda inferior discreta para se
/// ler como uma região própria do app em vez de uma faixa solta.
class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.profile,
    required this.mostrarSinoNotificacoes,
  });

  final Profile profile;
  final bool mostrarSinoNotificacoes;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).surfaceColors.pageBackground,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).surfaceColors.border),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (mostrarSinoNotificacoes) ...[
            const NotificationBell(),
            const SizedBox(width: AppSpacing.md),
          ],
          // Densidade compacta reduz um pouco a presença visual do seletor
          // sem remover os rótulos "Claro"/"Escuro" (continuam clicáveis e
          // legíveis — só ocupam menos espaço).
          Theme(
            data: Theme.of(
              context,
            ).copyWith(visualDensity: VisualDensity.compact),
            child: const ThemeToggleButton(),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(child: UserProfileHeader(profile: profile)),
        ],
      ),
    );
  }
}

/// Navegação inferior do celular: uma aba por rota-raiz (ver [NavTab]);
/// "Escanear" só no Android. Aparece apenas nas raízes das abas — formulários,
/// detalhes e demais telas internas ficam sem barra — e some com o teclado
/// aberto. A aba selecionada vem da rota real, nunca de um valor padrão.
class _MobileBottomBar extends StatelessWidget {
  const _MobileBottomBar({
    required this.currentRoute,
    required this.podeEscanear,
    required this.onNavigate,
  });

  final String currentRoute;
  final bool podeEscanear;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final atual = NavLocation.abaDe(currentRoute);
    if (atual == null || MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }

    final abas = [
      for (final aba in NavTab.values)
        if (aba != NavTab.escanear || podeEscanear) aba,
    ];
    // No scanner (só Android) a aba existe; fora do Android ele nunca é
    // alcançável por esta barra.
    final indice = abas.indexOf(atual);
    if (indice < 0) return const SizedBox.shrink();

    const icones = {
      NavTab.inicio: Icons.home_outlined,
      NavTab.patrimonios: Icons.inventory_2_outlined,
      NavTab.escanear: Icons.qr_code_scanner,
      NavTab.movimentacoes: Icons.swap_horiz_outlined,
    };

    return InvTecBottomNav(
      selectedIndex: indice,
      onSelected: (i) => onNavigate(abas[i].rota),
      items: [
        for (final aba in abas)
          BottomNavItem(icon: icones[aba]!, label: aba.rotulo),
      ],
    );
  }
}
