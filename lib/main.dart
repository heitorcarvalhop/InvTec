import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/env_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // PROMPT 11.3.4.1 — quando o ambiente foi selecionado explicitamente via
  // `--dart-define-from-file` (ver `EnvConfig.usaDartDefine`), `.env`
  // NUNCA é lido: nem para preencher valores ausentes, nem por engano. Um
  // build de homologação nunca toca o arquivo de produção; um build de
  // produção rodado sem a flag continua exatamente como antes.
  if (!EnvConfig.usaDartDefine) {
    await dotenv.load(fileName: '.env');
  }

  if (!EnvConfig.isSupabaseConfigured) {
    runApp(const _ConfigErrorApp());
    return;
  }

  // PROMPT 11.3.4, seção 2/3 — nunca "mostra" qual projeto está em uso só
  // implicitamente: todo start imprime o resumo seguro (rótulo de
  // ambiente + prévia do project ref, nunca a URL/chave completas — ver
  // `EnvConfig.resumoSeguroParaLog`). Um `.env` sem `SUPABASE_ENV`
  // declarado (ex.: o `.env` histórico deste projeto) aparece como
  // "AMBIENTE NÃO DECLARADO", nunca é presumido como produção.
  debugPrint('[InvTec] Ambiente Supabase em uso: ${EnvConfig.resumoSeguroParaLog}');

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
              EnvConfig.usaDartDefine
                  ? 'Configuração de --dart-define-from-file incompleta ou com '
                      'SUPABASE_ENV não reconhecido (precisa ser "producao" ou '
                      '"homologacao"). Confira o arquivo env/*.env usado.'
                  : 'Configuração ausente: defina SUPABASE_URL e '
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
