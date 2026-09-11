import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/env_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  if (!EnvConfig.isSupabaseConfigured) {
    runApp(const _ConfigErrorApp());
    return;
  }

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabasePublishableKey,
  );

  runApp(const ProviderScope(child: InvTecApp()));
}

/// Tela mínima exibida quando o app não consegue nem começar a inicializar
/// o Supabase — configuração ausente é um erro de ambiente de
/// desenvolvimento, não algo para o usuário final resolver.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Configuração ausente: defina SUPABASE_URL e '
              'SUPABASE_PUBLISHABLE_KEY no arquivo .env antes de executar '
              'o InvTec.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
