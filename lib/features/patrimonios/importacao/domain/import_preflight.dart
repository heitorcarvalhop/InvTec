import '../../../setores/domain/setor.dart';
import 'text_similarity.dart';

/// Um problema encontrado pelo preflight — sempre uma frase pronta para
/// relatório, nunca um código a ser traduzido depois.
class PreflightIssue {
  const PreflightIssue(this.mensagem);

  final String mensagem;
}

/// Resultado de uma checagem de preflight (PROMPT 8.10): puro e sem
/// nenhuma dependência de rede — recebe dados já carregados (do Supabase
/// real ou de um fake em teste) e só decide se o estado encontrado é
/// suficiente para seguir com a análise/importação.
class PreflightCheckResult {
  const PreflightCheckResult({required this.ok, required this.issues});

  final bool ok;
  final List<PreflightIssue> issues;
}

/// Checagens de pré-condição antes de qualquer análise/importação real
/// (seção 1/3 do PROMPT 8.10) — nunca decide sozinho continuar quando o
/// catálogo real está incompleto ou ambíguo: só relata "ok" quando o estado
/// bate exatamente com o esperado.
class ImportPreflight {
  const ImportPreflight._();

  /// Confirma que existe exatamente UMA gerência com [sigla] cadastrada E
  /// ativa entre [setores] — falha tanto quando não há nenhuma quanto
  /// quando há mais de uma (ambiguidade) ou quando a única encontrada está
  /// inativa.
  static PreflightCheckResult validarGerenciaUnica({
    required List<Setor> setores,
    required String sigla,
  }) {
    final candidatos = setores.where((s) => s.sigla == sigla).toList();
    if (candidatos.isEmpty) {
      return PreflightCheckResult(
        ok: false,
        issues: [PreflightIssue("Nenhuma gerência com sigla '$sigla' encontrada no Supabase.")],
      );
    }
    if (candidatos.length > 1) {
      return PreflightCheckResult(
        ok: false,
        issues: [
          PreflightIssue(
            "Encontradas ${candidatos.length} gerências com sigla '$sigla' — "
            'esperado exatamente 1. Ambiguidade não pode ser resolvida automaticamente.',
          ),
        ],
      );
    }
    final unica = candidatos.single;
    if (!unica.ativo) {
      return PreflightCheckResult(
        ok: false,
        issues: [PreflightIssue("A gerência '$sigla' existe, mas está inativa.")],
      );
    }
    return const PreflightCheckResult(ok: true, issues: []);
  }

  /// Confirma que todos os [nomesEsperados] estão presentes em
  /// [nomesEncontrados] (comparação normalizada — trim/case/acentos, nunca
  /// fuzzy) — usado tanto para as 15 localizações oficiais quanto para
  /// qualquer outra lista de nomes que o catálogo real precisa conter.
  /// Nomes extras em [nomesEncontrados] não são um problema por si só.
  static PreflightCheckResult validarNomesEsperados({
    required List<String> nomesEncontrados,
    required List<String> nomesEsperados,
  }) {
    final normalizados = nomesEncontrados.map(normalizarTextoComparacao).toSet();
    final faltando = [
      for (final esperado in nomesEsperados)
        if (!normalizados.contains(normalizarTextoComparacao(esperado))) esperado,
    ];
    if (faltando.isEmpty) return const PreflightCheckResult(ok: true, issues: []);
    return PreflightCheckResult(
      ok: false,
      issues: [for (final nome in faltando) PreflightIssue("Não encontrado/ativo no catálogo real: '$nome'.")],
    );
  }
}
