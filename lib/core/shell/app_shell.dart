import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../responsive/breakpoints.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('InvTec'),
        actions: [
          const ThemeToggleButton(),
          const SizedBox(width: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(child: UserProfileHeader(profile: profile)),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationSidebar(
            currentRoute: currentRoute,
            items: items,
            onNavigate: onNavigate,
            onLogout: onLogout,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
