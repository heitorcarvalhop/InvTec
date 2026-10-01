import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config.dart';
import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_controller.dart';

class InvTecApp extends ConsumerWidget {
  const InvTecApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    // Enquanto a preferência salva ainda não carregou, assume claro em vez
    // de travar a UI esperando.
    final themeMode = ref.watch(themeModeControllerProvider).value ?? ThemeMode.light;

    return MaterialApp.router(
      title: 'InvTec',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // Faixa vermelha com o nome do ambiente, visível em builds debug/profile
      // sempre que o Supabase ativo não estiver declarado como produção (um
      // `.env` sem `SUPABASE_ENV` nunca é tratado como produção). Some em
      // builds release para não aparecer ao usuário final.
      builder: (context, child) {
        if (child == null || kReleaseMode || EnvConfig.isProducao) return child ?? const SizedBox.shrink();
        return Banner(
          message: EnvConfig.supabaseEnv.isEmpty ? 'AMBIENTE?' : EnvConfig.supabaseEnv.toUpperCase(),
          location: BannerLocation.topStart,
          color: Colors.red.shade700,
          child: child,
        );
      },
    );
  }
}
