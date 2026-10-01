import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Acesso centralizado às variáveis de ambiente da aplicação.
///
/// Duas fontes possíveis, nunca misturadas na mesma execução:
///   1. `--dart-define-from-file=env/homologacao.env` (ou `env/producao.env`):
///      valores compilados como constantes (`String.fromEnvironment`) — o
///      binário não contém as credenciais do outro ambiente. Quando usado,
///      `.env` nunca é lido.
///   2. Ausência de `--dart-define-from-file`: `.env` na raiz do projeto,
///      carregado em runtime por `dotenv.load()` em `main.dart`. É o
///      caminho padrão (`flutter run`/`flutter build` sem flags extras).
///
/// As credenciais reais nunca ficam no código-fonte: `env/*.env` (fora o
/// `.example`) e `.env` são sempre ignorados pelo Git.
class EnvConfig {
  EnvConfig._();

  static const String _defineSupabaseEnv = String.fromEnvironment('SUPABASE_ENV');
  static const String _defineSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _defineSupabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String _defineComparacaoExecucaoHabilitada = String.fromEnvironment('COMPARACAO_EXECUCAO_HABILITADA');

  /// true quando o ambiente foi selecionado explicitamente via
  /// `--dart-define-from-file` — nesse caso [supabaseUrl]/
  /// [supabasePublishableKey]/[supabaseEnv] vêm só das constantes
  /// compiladas, `.env` nunca é consultado, mesmo que exista no disco.
  static bool get usaDartDefine => _defineSupabaseEnv.trim().isNotEmpty;

  static String get supabaseUrl {
    if (usaDartDefine) return _defineSupabaseUrl.trim();
    try {
      return dotenv.env['SUPABASE_URL'] ?? '';
    } catch (_) {
      return '';
    }
  }

  static String get supabasePublishableKey {
    if (usaDartDefine) return _defineSupabasePublishableKey.trim();
    try {
      return dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Rótulo explícito de qual projeto está em uso ("producao"/
  /// "homologacao"), nunca inferido do nome de arquivo nem da URL sozinha.
  /// Vazio quando nenhuma fonte declara `SUPABASE_ENV`, ou quando
  /// `dotenv.load()` nunca rodou (ex.: widget tests que constroem
  /// `InvTecApp` sem passar por `main()`, onde `dotenv.env` lançaria
  /// `NotInitializedError`, capturado aqui). Sempre tratado como
  /// "desconhecido" nesse caso — nunca como produção por padrão.
  static String get supabaseEnv {
    if (usaDartDefine) return _defineSupabaseEnv.trim().toLowerCase();
    try {
      return (dotenv.env['SUPABASE_ENV'] ?? '').trim().toLowerCase();
    } catch (_) {
      return '';
    }
  }

  static bool get isHomologacao => supabaseEnv == 'homologacao';
  static bool get isProducao => supabaseEnv == 'producao';
  static bool get _ambienteReconhecido => isProducao || isHomologacao;

  /// Ambiente desconhecido deve falhar de forma segura: quando selecionado
  /// via `--dart-define-from-file`, um `SUPABASE_ENV` que não seja
  /// literalmente "producao" nem "homologacao" invalida a configuração
  /// inteira, mesmo com URL/chave presentes. O caminho `.env` (sem
  /// dart-define) não tem essa exigência.
  static bool get isSupabaseConfigured {
    if (usaDartDefine && !_ambienteReconhecido) return false;
    return supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
  }

  /// "project ref" (subdomínio) extraído de [supabaseUrl] — não é uma
  /// credencial, mas ainda assim nunca é logado por inteiro; ver
  /// [resumoSeguroParaLog].
  static String? get supabaseProjectRef {
    final match = RegExp(r'^https://([a-z0-9]+)\.supabase\.co').firstMatch(supabaseUrl);
    return match?.group(1);
  }

  /// Trava operacional do modo ADMIN "Comparar e Atualizar": desabilitada
  /// por padrão, só liga com `COMPARACAO_EXECUCAO_HABILITADA` explicitamente
  /// igual a `"true"`. Independente de [isProducao]/`kReleaseMode` — é só
  /// uma proteção adicional, nunca um substituto da validação ADMIN feita
  /// no PostgreSQL (`private.has_perfil('ADMIN')`), que continua sendo a
  /// autoridade real. Não controla a comparação/revisão de divergências,
  /// que continuam disponíveis ao ADMIN mesmo com a execução desabilitada.
  static bool get comparacaoExecucaoHabilitada {
    final valor = usaDartDefine
        ? _defineComparacaoExecucaoHabilitada.trim().toLowerCase()
        : _comparacaoExecucaoHabilitadaDotenv;
    return valor == 'true';
  }

  static String get _comparacaoExecucaoHabilitadaDotenv {
    try {
      return (dotenv.env['COMPARACAO_EXECUCAO_HABILITADA'] ?? '').trim().toLowerCase();
    } catch (_) {
      return '';
    }
  }

  static String get resumoSeguroParaLog {
    final ref = supabaseProjectRef;
    final ambiente = supabaseEnv.isEmpty ? 'AMBIENTE NÃO DECLARADO (SUPABASE_ENV ausente)' : supabaseEnv.toUpperCase();
    final origem = usaDartDefine ? '--dart-define-from-file' : '.env (padrão)';
    final refResumido = ref == null ? 'ref desconhecido' : '${ref.substring(0, 4)}…';
    return '$ambiente via $origem ($refResumido)';
  }
}
