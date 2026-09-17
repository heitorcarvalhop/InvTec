import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_controller.dart';

class InvTecApp extends ConsumerWidget {
  const InvTecApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    // Enquanto a preferência salva ainda não carregou (raríssimo, só no
    // instante do cold start), assume claro — nunca trava a UI esperando.
    final themeMode = ref.watch(themeModeControllerProvider).value ?? ThemeMode.light;

    return MaterialApp.router(
      title: 'InvTec',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
