import '../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../../setores/domain/setor.dart';
import 'sei_item_extraido.dart';

/// Estado de uma linha depois do cruzamento READ-ONLY com o InvTec (PROMPT
/// 11.1, seção 20) — nunca decide uma escrita, só classifica a linha para a
/// revisão humana.
enum SeiStatusLinha {
  /// Patrimônio existe, origem confere, destino identificado, tipo de
  /// movimentação compatível com o status atual.
  pronto,

  /// Informativo, não bloqueante (ex.: equipamento com descrição diferente,
  /// chamado ausente).
  aviso,

  /// Não pode seguir sem correção/decisão humana fora desta V1 (ex.:
  /// patrimônio não encontrado, origem diverge do setor atual, destino não
  /// encontrado, duplicado no documento).
  bloqueado,
}

/// Um texto do documento comparado contra uma entidade do InvTec (PROMPT
/// 11.1, seção 17/18) — nunca substitui o texto original, só guarda os três
/// lados da comparação lado a lado para a UI mostrar com transparência.
class SeiComparacaoUnidade {
  const SeiComparacaoUnidade({this.valorOriginal, this.valorNormalizado, this.entidadeEncontrada});

  final String? valorOriginal;
  final String? valorNormalizado;
  final Setor? entidadeEncontrada;
}

/// Uma linha da revisão: o item extraído do PDF + o que foi encontrado no
/// InvTec (leitura em lote, nunca uma query por linha — seção 16) + o
/// veredito da validação. Puramente o resultado da análise; nenhum campo
/// aqui é enviado a uma RPC nesta etapa.
class SeiValidacaoItem {
  const SeiValidacaoItem({
    required this.item,
    required this.status,
    this.checks = const [],
    this.avisos = const [],
    this.bloqueios = const [],
    this.patrimonioEncontrado,
    this.origem = const SeiComparacaoUnidade(),
    this.destino = const SeiComparacaoUnidade(),
    this.equipamentoCompativel,
  });

  final SeiItemExtraido item;
  final SeiStatusLinha status;

  final List<String> checks;
  final List<String> avisos;
  final List<String> bloqueios;

  /// `null` quando o número do patrimônio do documento não foi encontrado no
  /// InvTec — por si só já é um bloqueio (ver [bloqueios]).
  final PatrimonioDetalhe? patrimonioEncontrado;

  final SeiComparacaoUnidade origem;
  final SeiComparacaoUnidade destino;

  /// Comparação informativa (seção 19) entre o equipamento do documento e o
  /// tipo/marca/modelo cadastrados — `null` quando não há base de
  /// comparação (ex.: patrimônio não encontrado). Nunca bloqueante sozinha.
  final bool? equipamentoCompativel;
}
