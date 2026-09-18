import 'sei_documento_extraido.dart';
import 'sei_validacao_item.dart';

/// Resultado final da análise (PROMPT 11.1) — documento extraído + cada
/// linha já validada contra o InvTec. É o único objeto que a tela de
/// revisão precisa; termina o fluxo da V1 ("Concluir análise" — seção 34),
/// nunca alimenta `registrarMovimentacao`.
class SeiAnaliseResultado {
  const SeiAnaliseResultado({required this.documento, required this.itens});

  final SeiDocumentoExtraido documento;
  final List<SeiValidacaoItem> itens;

  int get totalItens => itens.length;
  int get totalProntos => itens.where((i) => i.status == SeiStatusLinha.pronto).length;
  int get totalAvisos => itens.where((i) => i.status == SeiStatusLinha.aviso).length;
  int get totalBloqueados => itens.where((i) => i.status == SeiStatusLinha.bloqueado).length;
}
