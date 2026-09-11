import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Acesso centralizado às variáveis de ambiente da aplicação.
///
/// As credenciais reais nunca ficam no código-fonte: elas são carregadas
/// em tempo de execução a partir do arquivo `.env` (não versionado).
class EnvConfig {
  EnvConfig._();

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';

  static String get supabasePublishableKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
