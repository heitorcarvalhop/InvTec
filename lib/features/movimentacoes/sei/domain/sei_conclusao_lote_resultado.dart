import 'sei_conclusao_item_resultado.dart';

/// Um elemento do array `itens` do envelope de `concluir_itens_documento_sei_lote`
/// — `{item_id, resultado}`. O `resultado` de cada item tem EXATAMENTE o
/// mesmo formato `{ja_concluido, documento, item, movimentacao}` devolvido
/// por `concluir_item_documento_sei` (a RPC de lote chama a RPC individual
/// uma vez por item, sem alterar o formato dela), por isso reaproveita
/// [SeiConclusaoItemResultado.fromJson] sem nenhuma adaptação.
class SeiConclusaoLoteItemResultado {
  const SeiConclusaoLoteItemResultado({required this.itemId, required this.resultado});

  factory SeiConclusaoLoteItemResultado.fromJson(Map<String, dynamic> json) {
    return SeiConclusaoLoteItemResultado(
      itemId: json['item_id'] as String,
      resultado: SeiConclusaoItemResultado.fromJson(json['resultado'] as Map<String, dynamic>),
    );
  }

  final String itemId;
  final SeiConclusaoItemResultado resultado;
}

/// Resultado de `concluir_itens_documento_sei_lote` — o jsonb
/// `{ja_executado, documento, itens: [{item_id, resultado}]}` devolvido pela
/// RPC. Este é o formato REAL, instalado e homologado — nenhum campo aqui é
/// inventado ou presumido.
///
/// Assim como [SeiConclusaoItemResultado], `documento` na RPC é só a linha
/// bruta de `documentos_sei` (via `to_jsonb`, sem embed de autor nem de
/// itens): só a identidade e a versão FINAL (depois de concluir TODOS os
/// itens do lote) são expostas aqui — a tela precisa reler o documento
/// completo (`obterPorId`) depois de um lote bem-sucedido.
class SeiConclusaoLoteResultado {
  const SeiConclusaoLoteResultado({
    required this.jaExecutado,
    required this.documentoId,
    required this.documentoVersao,
    required this.itens,
  });

  factory SeiConclusaoLoteResultado.fromJson(Map<String, dynamic> json) {
    final documento = json['documento'] as Map<String, dynamic>;
    final itensJson = json['itens'] as List<dynamic>;
    return SeiConclusaoLoteResultado(
      jaExecutado: json['ja_executado'] as bool? ?? false,
      documentoId: documento['id'] as String,
      documentoVersao: (documento['versao'] as num).toInt(),
      itens: itensJson.cast<Map<String, dynamic>>().map(SeiConclusaoLoteItemResultado.fromJson).toList(),
    );
  }

  /// `true` quando este `lote_id` JÁ tinha sido executado com sucesso antes
  /// (retry idêntico, com TODOS os demais parâmetros iguais): a RPC não
  /// travou documento/itens/patrimônios, não escreveu nada, não criou
  /// movimentação nem evento novos — só devolveu o `resultado` já registrado
  /// em `documentos_sei_lotes_conclusao`, com este campo sobrescrito para
  /// `true` (`v_lote.resultado || jsonb_build_object('ja_executado', true)`,
  /// migration acima, passo 6). `false` numa primeira execução bem-sucedida.
  final bool jaExecutado;

  final String documentoId;

  /// Versão do documento DEPOIS de concluir TODOS os itens do lote — a
  /// versão avança UMA VEZ POR ITEM concluído, não uma vez só para o lote
  /// inteiro; este é o valor final da cadeia, útil para a próxima escrita
  /// no mesmo documento.
  final int documentoVersao;

  /// Um elemento por item concluído, na ordem em que a RPC de fato os
  /// processou (`order by patrimonio_id, id`) — não necessariamente a ordem
  /// em que os ids foram enviados em `p_item_ids`.
  final List<SeiConclusaoLoteItemResultado> itens;
}
