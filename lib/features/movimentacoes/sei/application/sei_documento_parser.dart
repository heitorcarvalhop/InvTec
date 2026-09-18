import '../domain/sei_documento_extraido.dart';

/// Fronteira entre "texto já extraído do PDF" e "modelo estruturado do
/// documento" (PROMPT 11.1, seção 28) — puramente texto→modelo, nunca lida
/// com bytes de PDF nem com Supabase. Isso permite, no futuro, um
/// `SeiAiParser` (IA como fallback) implementar a mesma interface sem
/// reescrever a extração de PDF nem a UI: só troca QUEM interpreta o texto
/// já extraído.
///
/// V1 só tem [SeiDeterministicParser] (`data/sei_despacho_parser.dart`) —
/// regras/âncoras determinísticas, sem nenhuma IA externa (seção 28).
abstract class SeiDocumentoParser {
  /// [textoPorPagina] já veio da camada de extração de PDF (`SeiPdfTextExtractor`)
  /// — uma entrada por página, 1-based na ordem do documento.
  Future<SeiDocumentoExtraido> analisar({
    required String nomeArquivo,
    required int tamanhoBytes,
    required String hashSha256,
    required List<String> textoPorPagina,
  });
}
