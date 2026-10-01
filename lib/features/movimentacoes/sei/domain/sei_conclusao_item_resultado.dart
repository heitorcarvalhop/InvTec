import '../../domain/movimentacao.dart';
import 'sei_item_pendente.dart';

/// Resultado de `concluir_item_documento_sei` (PROMPT 11.4.3) — o jsonb
/// `{ja_concluido, documento, item, movimentacao}` devolvido pela RPC.
///
/// Reutiliza os modelos já existentes: [item] é o [SeiItemPendente] (a linha
/// inteira de `documentos_sei_itens`; os embeds de nome — setor, patrimônio —
/// não vêm da RPC e ficam nulos) e [movimentacao] é a [Movimentacao] efetiva.
/// O `documento` da RPC é só a linha de `documentos_sei` (sem itens nem
/// totais), então só a identidade e a NOVA versão são expostas: a tela relê o
/// documento completo (`obterPorId`) depois de uma conclusão.
class SeiConclusaoItemResultado {
  const SeiConclusaoItemResultado({
    required this.jaConcluido,
    required this.documentoId,
    required this.documentoVersao,
    required this.item,
    required this.movimentacao,
  });

  factory SeiConclusaoItemResultado.fromJson(Map<String, dynamic> json) {
    final documento = json['documento'] as Map<String, dynamic>;
    return SeiConclusaoItemResultado(
      jaConcluido: json['ja_concluido'] as bool? ?? false,
      documentoId: documento['id'] as String,
      documentoVersao: (documento['versao'] as num).toInt(),
      item: SeiItemPendente.fromJson(json['item'] as Map<String, dynamic>),
      movimentacao: Movimentacao.fromJson(json['movimentacao'] as Map<String, dynamic>),
    );
  }

  /// `true` quando o item JÁ estava concluído: a RPC não criou uma segunda
  /// movimentação e devolveu a existente (repetição/clique duplo/timeout).
  final bool jaConcluido;

  final String documentoId;
  final int documentoVersao;
  final SeiItemPendente item;
  final Movimentacao movimentacao;
}
