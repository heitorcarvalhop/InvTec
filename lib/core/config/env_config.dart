import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Acesso centralizado às variáveis de ambiente da aplicação.
///
/// PROMPT 11.3.4.1 — duas fontes possíveis, NUNCA misturadas na mesma
/// execução:
///
///   1. `--dart-define-from-file=env/homologacao.env` (ou
///      `env/producao.env`) — seleção EXPLÍCITA no comando de
///      `flutter run`/`flutter build`, valores compilados como constantes
///      (`String.fromEnvironment`) — o binário resultante fisicamente não
///      contém as credenciais do outro ambiente, porque elas nunca foram
///      passadas ao compilador. Sempre que `SUPABASE_ENV` chega por esta
///      via, `.env` NUNCA é lido — não há nenhuma cópia manual de arquivo,
///      nenhum passo destrutivo.
///   2. Ausência de `--dart-define-from-file` — comportamento HISTÓRICO
///      preservado sem alteração: `.env` na raiz do projeto, carregado em
///      runtime por `dotenv.load()` em `main.dart`. Continua sendo o
///      caminho de produção padrão (`flutter run`/`flutter build` sem
///      flags extras) — ver seção "preservar produção atual" do PROMPT
///      11.3.4.1.
///
/// As credenciais reais nunca ficam no código-fonte: `env/*.env` (fora o
/// `.example`) e `.env` são sempre ignorados pelo Git.
class EnvConfig {
  EnvConfig._();

  static const String _defineSupabaseEnv = String.fromEnvironment('SUPABASE_ENV');
  static const String _defineSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _defineSupabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String _defineComparacaoExecucaoHabilitada = String.fromEnvironment('COMPARACAO_EXECUCAO_HABILITADA');

  /// true quando o ambiente foi selecionado EXPLICITAMENTE no comando de
  /// build/execução (`--dart-define-from-file`) — nesse caso [supabaseUrl]/
  /// [supabasePublishableKey]/[supabaseEnv] vêm SÓ das constantes
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

  /// Rótulo EXPLÍCITO de qual projeto está em uso ("producao"/
  /// "homologacao"), nunca inferido do nome de arquivo nem da URL sozinha.
  /// Vazio quando: nenhuma fonte declara `SUPABASE_ENV`; OU quando
  /// `dotenv.load()` nunca rodou (ex.: widget tests que constroem
  /// `InvTecApp` sem passar por `main()`) — `dotenv.env` lança
  /// `NotInitializedError` nesse caso, capturado aqui para nunca derrubar
  /// a UI. Em qualquer caso vazio, tratado como "desconhecido" — nunca
  /// como produção nem como homologação por padrão.
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

  /// "Ambiente desconhecido deve falhar de forma segura" (PROMPT
  /// 11.3.4.1, seção 2): quando o ambiente foi selecionado via
  /// `--dart-define-from-file`, um `SUPABASE_ENV` que não seja literalmente
  /// "producao" nem "homologacao" (ex.: erro de digitação no arquivo)
  /// invalida a configuração INTEIRA — mesmo que URL/chave estejam
  /// presentes — em vez de deixar o app subir com um rótulo de ambiente
  /// não reconhecido. O caminho histórico (`.env`, sem dart-define) NÃO
  /// tem essa exigência: preserva o comportamento atual de produção, cujo
  /// `.env` ainda não declara `SUPABASE_ENV`.
  static bool get isSupabaseConfigured {
    if (usaDartDefine && !_ambienteReconhecido) return false;
    return supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
  }

  /// "project ref" (subdomínio) extraído de [supabaseUrl] — não é uma
  /// credencial (é a parte pública/visível da URL, presente em toda
  /// requisição de rede), mas ainda assim nunca é logado por inteiro; ver
  /// [resumoSeguroParaLog].
  static String? get supabaseProjectRef {
    final match = RegExp(r'^https://([a-z0-9]+)\.supabase\.co').firstMatch(supabaseUrl);
    return match?.group(1);
  }

  /// Resumo seguro para exibir em UI/logs/relatórios: nunca inclui a URL
  /// completa nem a publishable key — só o rótulo de ambiente, a origem
  /// da configuração (dart-define explícito vs. `.env` histórico) e os 4
  /// primeiros caracteres do project ref (suficiente para uma conferência
  /// visual humana, insuficiente para ser usado como credencial).
  /// PROMPT 11.6.5, seção 9 — trava de liberação OPERACIONAL da execução
  /// real do modo ADMIN "Comparar e Atualizar" (PROMPT 11.6.4):
  /// DESABILITADA por padrão, precisa de `COMPARACAO_EXECUCAO_HABILITADA`
  /// EXPLICITAMENTE igual a `"true"` — em qualquer outra situação (ausente,
  /// vazio, "false", erro de digitação) o resultado é `false`, nunca `true`
  /// por engano. Deliberadamente INDEPENDENTE de [isProducao]/`kReleaseMode`
  /// (a migration pode existir num banco de homologação/produção muito antes
  /// de a funcionalidade estar autorizada para uso real, e um build de
  /// debug não deveria ser a única barreira) — é só uma proteção
  /// OPERACIONAL adicional, nunca um substituto da validação ADMIN feita no
  /// PostgreSQL (`private.has_perfil('ADMIN')` dentro da própria RPC), que
  /// continua sendo a autoridade real mesmo que este valor seja alterado
  /// incorretamente. NUNCA controla a comparação/revisão de divergências
  /// (PROMPT 11.6.2/11.6.3), que continuam disponíveis ao ADMIN mesmo com a
  /// execução desabilitada — só [ComparacaoExecucaoController.confirmar] e a
  /// UI de execução (`import_comparacao_resumo_step.dart`) consultam isto.
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
