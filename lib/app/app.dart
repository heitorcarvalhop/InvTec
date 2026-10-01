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
      // PROMPT 11.3.4, seção 3 — "mostrar claramente qual projeto será
      // utilizado" não vale só para scripts: sempre que o `.env` ativo NÃO
      // declarar explicitamente `SUPABASE_ENV=producao`, a faixa fica
      // visível na tela inteira (inclusive um `.env` sem essa chave — o
      // caso "ambiente não declarado" nunca é tratado como produção).
      //
      // PROMPT 11.5.17 — essa faixa é um indicador para quem está
      // DESENVOLVENDO (rodar/depurar localmente sem saber, de bate-pronto,
      // se está contra homologação ou produção), nunca algo que o pacote
      // final para os funcionários da GETEC deveria mostrar. O `.env` de
      // produção deste projeto historicamente não declara `SUPABASE_ENV`
      // (comportamento preservado, ver `EnvConfig.supabaseEnv`), então
      // `isProducao` sozinho é `false` mesmo apontando para o projeto
      // Supabase certo — SEM o `!kReleaseMode` abaixo, a faixa vermelha
      // "AMBIENTE?" apareceria também no build Release de distribuição.
      // `kReleaseMode` nunca é `true` num `flutter run`/`flutter build
      // --debug`/`--profile` (só em `--release`), então debug/profile
      // continuam EXATAMENTE como antes — nada muda para quem desenvolve.
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
