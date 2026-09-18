import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/profile.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'navigation_items.dart';
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

    if (context.screenSize == ScreenSize.mobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('InvTec'),
          actions: const [ThemeToggleButton(compact: true), SizedBox(width: AppSpacing.sm)],
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
      );
    }

    // Sem `Scaffold.appBar`: uma AppBar no Scaffold cria uma faixa de
    // largura total ACIMA de tudo, empurrando a sidebar para baixo dela —
    // exatamente o que a sidebar full-height (PROMPT 9.3.4) não pode ter.
    // Em vez disso, sidebar e conteúdo (com sua própria topbar) ficam lado
    // a lado dentro do `body`, os dois começando no topo absoluto da
    // janela.
    return Scaffold(
      body: Row(
        children: [
          NavigationSidebar(
            currentRoute: currentRoute,
            items: items,
            onNavigate: onNavigate,
            onLogout: onLogout,
          ),
          Expanded(
            child: Column(
              children: [
                _DesktopTopBar(profile: profile),
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
/// direita, sem título de produto (a marca "InvTec" vive só na sidebar —
/// PROMPT 9.3.3/9.3.4). Mesma cor do fundo da página e sem borda/sombra
/// própria, para não parecer uma segunda barra empilhada sobre o layout.
class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      color: Theme.of(context).surfaceColors.pageBackground,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const ThemeToggleButton(),
          const SizedBox(width: AppSpacing.lg),
          UserProfileHeader(profile: profile),
        ],
      ),
    );
  }
}
