/// Confiança da extração de um campo (PROMPT 11.1, seção 21) — não precisa
/// virar percentual na UI; serve só para decidir se um item PRONTO/AVISO
/// exige revisão mais atenta ou é rebaixado a BLOQUEADO quando o campo é
/// crítico (ex.: número do patrimônio ambíguo).
enum SeiConfianca { alta, media, baixa }

/// Um bem (linha da tabela) extraído do documento SEI — evidência bruta do
/// PDF, nunca cruzada com o InvTec aqui (isso é o [SeiValidacaoItem], na
/// camada de análise). Nenhum campo é obrigatório: o parser nunca inventa um
/// valor que não encontrou (seção 6 — "não exigir que todos os campos
/// existam").
class SeiItemExtraido {
  const SeiItemExtraido({
    required this.linha,
    required this.paginaOrigem,
    this.equipamento,
    this.numeroPatrimonio,
    this.unidadeOrigemTexto,
    this.unidadeDestinoTexto,
    this.numeroChamado,
    this.confiancaPatrimonio = SeiConfianca.alta,
    this.confiancaDestino = SeiConfianca.alta,
    this.observacoesParsing = const [],
  });

  /// Posição (1-based) do item na ordem em que apareceu no documento — nunca
  /// reordenado, mesmo que a revisão na UI permita ordenar/filtrar por
  /// status.
  final int linha;

  /// Página (1-based) onde o item começa — mostrado no detalhe da linha
  /// (seção 24) para o usuário conferir contra o PDF original.
  final int paginaOrigem;

  final String? equipamento;
  final String? numeroPatrimonio;
  final String? unidadeOrigemTexto;
  final String? unidadeDestinoTexto;
  final String? numeroChamado;

  final SeiConfianca confiancaPatrimonio;
  final SeiConfianca confiancaDestino;

  /// Observações do PRÓPRIO parsing desta linha (ex.: "número do patrimônio
  /// reconstruído a partir de dígitos intercalados no texto") — evidência
  /// para o usuário, nunca escondida.
  final List<String> observacoesParsing;
}
