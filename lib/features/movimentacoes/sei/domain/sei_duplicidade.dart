import '../../domain/movimentacao_listagem_item.dart';

/// Resultado da pré-checagem READ-ONLY de duplicidade contra o histórico já
/// registrado no InvTec — nunca cria nem altera nada, só classifica. Nem o
/// hash do PDF sozinho, nem o número do
/// documento SEI sozinho, bastam para decidir duplicidade: o mesmo
/// documento legitimamente cobre vários patrimônios diferentes, e o mesmo
/// PDF pode ser reexportado com bytes distintos (hash muda) — por isso a
/// comparação é por patrimônio + tipo + destino + chamado, todos dentro do
/// mesmo `numero_documento`.
enum SeiDuplicidadeStatus {
  /// Nenhuma movimentação deste patrimônio referencia o mesmo documento SEI.
  semCorrespondencia,

  /// Existe movimentação deste patrimônio para o mesmo documento SEI, do
  /// mesmo tipo, mas com destino ou chamado divergentes do que o PDF propõe
  /// agora — pode ser erro de digitação, reprocessamento parcial ou
  /// coincidência; exige olhar humano antes de qualquer seleção.
  possivelDuplicidade,

  /// Já existe movimentação deste patrimônio, para o mesmo documento SEI,
  /// com o MESMO tipo/destino/chamado propostos — o procedimento deste item
  /// já foi registrado.
  jaRegistrada,

  /// Existe movimentação deste patrimônio para o mesmo documento SEI, mas
  /// de um TIPO diferente (ex.: já houve uma BAIXA por este despacho) — a
  /// interpretação de TRANSFERENCIA do documento pode não se aplicar mais a
  /// este item.
  exigeRevisao,
}

class SeiDuplicidadeResultado {
  const SeiDuplicidadeResultado({required this.status, this.correspondente, required this.detalhe});

  final SeiDuplicidadeStatus status;

  /// A movimentação já registrada que motivou o veredito — `null` só quando
  /// [status] é [SeiDuplicidadeStatus.semCorrespondencia].
  final MovimentacaoListagemItem? correspondente;

  final String detalhe;
}
