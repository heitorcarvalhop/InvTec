import '../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../domain/sei_documento_pendente.dart';
import '../domain/sei_item_pendente.dart';
import 'sei_conclusao_plano.dart';

/// mesmo limite de `concluir_itens_documento_sei_lote`
/// (`v_limite_itens constant integer := 200;`, migration
/// `20260928100000_add_concluir_itens_documento_sei_lote.sql`) — checado
/// aqui ANTES de qualquer chamada de rede, para a UI nunca depender só do
/// `P0001` do servidor para avisar o usuário.
const limiteItensLote = 200;

/// O planejamento de UM item dentro da seleção do lote — reaproveita
/// [planejarConclusaoEntrega] sem alteração: o plano individual de cada
/// item é o mesmo que o diálogo de conclusão individual calcularia sozinho.
class SeiPlanoConclusaoLoteItem {
  const SeiPlanoConclusaoLoteItem({required this.item, required this.plano});

  final SeiItemPendente item;
  final SeiPlanoConclusao plano;

  String get itemId => item.id;
  String? get patrimonioId => item.patrimonioId;
}

/// O que a conclusão em LOTE de [itens] vai fazer, calculado só com dados
/// que a tela já tem — puro, sem I/O, mesmo espírito de
/// [planejarConclusaoEntrega]. A autoridade final continua sendo a RPC
/// `concluir_itens_documento_sei_lote`; isto só evita chamadas que ela
/// recusaria e mostra ao usuário, antes de confirmar, o que vai acontecer
/// com cada item selecionado.
class SeiPlanoConclusaoLote {
  const SeiPlanoConclusaoLote({required this.documentoId, required this.itens, required this.bloqueiosGerais});

  final String documentoId;

  /// Um elemento por item da SELEÇÃO EXPLÍCITA, na mesma ordem recebida —
  /// nunca filtra ou remove um item bloqueado: ele aparece aqui com seu
  /// próprio [SeiPlanoConclusaoLoteItem.plano] indicando o bloqueio.
  final List<SeiPlanoConclusaoLoteItem> itens;

  /// Bloqueios do LOTE como um todo (seleção vazia, limite excedido, itens/
  /// patrimônios duplicados, itens de outro documento) — SEPARADOS dos
  /// bloqueios de cada item ([SeiPlanoConclusaoLoteItem.plano.bloqueios]).
  /// Mesmo com esta lista vazia, o lote pode continuar bloqueado se
  /// QUALQUER item individual tiver bloqueio — ver [podeConfirmar].
  final List<String> bloqueiosGerais;

  int get totalSelecionado => itens.length;

  bool get algumItemBloqueado => itens.any((i) => !i.plano.podeConfirmar);

  /// `true` quando PELO MENOS UM item da seleção exigiria confirmação de
  /// limpeza de localização/responsável — a RPC só recebe UMA flag para o
  /// lote inteiro (`p_confirmar_limpeza_destino`), então a futura tela
  /// precisa de uma confirmação AGREGADA sempre que isto for `true`.
  bool get exigeConfirmacaoDeLimpezaAgregada => itens.any((i) => i.plano.exigeConfirmacaoDeLimpeza);

  /// `true` só quando NADA bloqueia: nem uma regra do lote como um todo
  /// ([bloqueiosGerais]), nem o plano de QUALQUER item individual da
  /// seleção. Nunca "a maioria pode, alguns não": um único item bloqueado
  /// bloqueia o lote INTEIRO — a seleção explícita nunca é reduzida
  /// silenciosamente para excluir só os itens problemáticos (isso é
  /// exclusividade de "Concluir todos os aptos", ver
  /// `sei_selecao_aptos_lote.dart`).
  bool get podeConfirmar => bloqueiosGerais.isEmpty && !algumItemBloqueado;
}

/// Monta o [SeiPlanoConclusaoLote] de [itensSelecionados] contra
/// [documento] e o estado ATUAL de cada patrimônio envolvido
/// ([patrimoniosPorItemId], indexado por [SeiItemPendente.id] — não por
/// `patrimonioId`, para cobrir também o item sem patrimônio resolvido,
/// `null`, que [planejarConclusaoEntrega] já trata como bloqueio).
SeiPlanoConclusaoLote planejarConclusaoLote({
  required SeiDocumentoPendente documento,
  required List<SeiItemPendente> itensSelecionados,
  required Map<String, PatrimonioDetalhe?> patrimoniosPorItemId,
}) {
  final bloqueiosGerais = <String>[];

  if (itensSelecionados.isEmpty) {
    bloqueiosGerais.add('Selecione ao menos um item para concluir em lote.');
  }

  if (itensSelecionados.length > limiteItensLote) {
    bloqueiosGerais.add(
      'A seleção tem ${itensSelecionados.length} itens — o limite é de $limiteItensLote itens por lote. '
      'Reduza a seleção.',
    );
  }

  final idsVistos = <String>{};
  final temIdRepetido = itensSelecionados.any((item) => !idsVistos.add(item.id));
  if (temIdRepetido) {
    bloqueiosGerais.add('A seleção contém o mesmo item repetido.');
  }

  final patrimonioIdsVistos = <String>{};
  final temPatrimonioRepetido = itensSelecionados.any(
    (item) => item.patrimonioId != null && !patrimonioIdsVistos.add(item.patrimonioId!),
  );
  if (temPatrimonioRepetido) {
    bloqueiosGerais.add('Dois ou mais itens selecionados apontam para o mesmo patrimônio.');
  }

  final temItemDeOutroDocumento = itensSelecionados.any((item) => item.documentoId != documento.id);
  if (temItemDeOutroDocumento) {
    bloqueiosGerais.add('A seleção contém itens de um documento diferente — um lote nunca mistura documentos.');
  }

  final itensPlano = [
    for (final item in itensSelecionados)
      SeiPlanoConclusaoLoteItem(
        item: item,
        plano: planejarConclusaoEntrega(
          documento: documento,
          item: item,
          patrimonioAtual: patrimoniosPorItemId[item.id],
        ),
      ),
  ];

  return SeiPlanoConclusaoLote(documentoId: documento.id, itens: itensPlano, bloqueiosGerais: bloqueiosGerais);
}
