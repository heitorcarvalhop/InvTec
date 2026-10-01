import '../domain/sei_pendencia_exceptions.dart';

/// Nome da RPC — usado no texto técnico e no log.
const operacaoConcluirItemSei = 'concluir_item_documento_sei';

/// PROMPT 11.5.5 — nome da RPC de conclusão em LOTE. Propaga, sem alteração,
/// todos os códigos de erro de [operacaoConcluirItemSei] (ela chama a RPC
/// individual por dentro, item a item) mais dois novos, só dela: `P0036` e
/// `P0037` — por isso reaproveita a MESMA [mensagemErroConclusaoSei] abaixo,
/// nunca uma função de mapeamento separada.
const operacaoConcluirItensSeiLote = 'concluir_itens_documento_sei_lote';

/// Mensagem COMPREENSÍVEL para o usuário de um erro de
/// `concluir_item_documento_sei` (PROMPT 11.4.3) OU de
/// `concluir_itens_documento_sei_lote` (PROMPT 11.5.5 — a RPC de lote chama a
/// individual por dentro, então qualquer código dela pode chegar aqui do
/// mesmo jeito). O texto cru do Postgres (com UUIDs e jargão) nunca é a
/// mensagem principal — fica só nos detalhes técnicos ([falhaDeConclusaoSei]).
///
/// Códigos definidos pela RPC individual:
///  * `P0030` estado inconsistente do item;
///  * `P0031` vínculo patrimonial incoerente;
///  * `P0032` origem/status do patrimônio divergente;
///  * `P0033` patrimônio movimentado depois da criação da pendência;
///  * `P0034` possível movimentação duplicada do mesmo documento;
///  * `P0035` confirmação necessária para a limpeza de localização/responsável;
/// e os já existentes `42501`, `P0001`, `P0002`, `P0010`.
///
/// Códigos definidos SÓ pela RPC de lote (PROMPT 11.5.5):
///  * `P0036` um ou mais itens do lote não estão mais PENDENTE (concluídos
///    ou cancelados por uma operação diferente deste `lote_id`) — a chamada
///    inteira é recusada, nenhum item do lote é concluído;
///  * `P0037` o mesmo `lote_id` já foi usado para uma operação com ao menos
///    um parâmetro diferente (documento, itens, versão esperada, observação,
///    confirmação de limpeza ou usuário) — nunca reaproveitado
///    silenciosamente para uma operação diferente.
String mensagemErroConclusaoSei({required String? codigo, required String mensagemDoServidor}) {
  final texto = mensagemDoServidor.toLowerCase();
  switch (codigo) {
    case '42501':
      return 'Você não tem permissão para concluir entregas.';
    case 'P0002':
      return 'Documento, item ou patrimônio não encontrado. Atualize a tela e confira o documento.';
    case 'P0010':
      return 'O documento foi alterado por outra pessoa desde que você o abriu. '
          'Nada foi concluído. Feche esta tela, confira o documento atualizado e tente novamente.';
    case 'P0030':
      return 'O estado deste item está inconsistente (por exemplo, concluído sem movimentação vinculada). '
          'Não tente de novo: peça a revisão da equipe técnica.';
    case 'P0031':
      return 'O vínculo do item com o patrimônio está incoerente: o número do patrimônio do item não corresponde ao '
          'patrimônio vinculado. Corrija o número do patrimônio pela edição do documento e tente novamente.';
    case 'P0032':
      return 'O estado atual do patrimônio diverge do que o documento espera (setor de origem ou situação). '
          'Revise o patrimônio antes de concluir esta entrega.';
    case 'P0033':
      return 'Este patrimônio foi movimentado depois que a pendência foi criada. '
          'Revise o histórico do patrimônio antes de concluir esta entrega.';
    case 'P0034':
      return 'Já existe uma movimentação deste patrimônio com o mesmo documento SEI (possível entrega duplicada). '
          'Revise o histórico do patrimônio antes de concluir.';
    case 'P0035':
      return 'A conclusão limparia a localização ou o responsável atual do patrimônio e essa consequência ainda não '
          'foi confirmada. Reabra a conclusão e confirme a limpeza.';
    case 'P0036':
      return 'Um ou mais itens selecionados não estão mais disponíveis para esta conclusão em lote (já foram '
          'concluídos ou cancelados por outra operação). Nada foi concluído. Atualize a tela, revise a seleção e '
          'tente novamente.';
    case 'P0037':
      return 'Esta conclusão em lote já havia sido registrada antes com parâmetros diferentes dos que estão sendo '
          'enviados agora. Não repita esta tentativa automaticamente: feche esta tela, releia o documento e comece '
          'uma nova conclusão.';
    case 'P0001':
      if (texto.contains('não está pendente')) {
        return 'Este item não está mais pendente (já foi concluído ou cancelado). Atualize a tela.';
      }
      if (texto.contains('só suporta transferencia')) {
        return 'Esta versão só conclui entregas de transferência entre setores.';
      }
      if (texto.contains('não tem setor de destino')) {
        return 'O setor de destino deste item ainda não foi definido. Corrija pela edição do documento.';
      }
      if (texto.contains('inexistente ou inativo')) {
        return 'O setor de destino não existe ou está inativo. Corrija o destino pela edição do documento.';
      }
      if (texto.contains('ainda está pendente')) {
        return 'A decisão sobre a localização ou o responsável de destino ainda está pendente. '
            'Defina pela edição do documento.';
      }
      if (texto.contains('movimentação interna') || texto.contains('precisa ser diferente da localização')) {
        return 'Movimentação dentro do mesmo setor exige uma localização de destino definida e diferente da atual.';
      }
      if (texto.contains('não pertence ao documento')) {
        return 'Este item não pertence ao documento informado. Atualize a tela.';
      }
      return 'O sistema recusou a conclusão desta entrega. Nada foi alterado. '
          'Veja os detalhes técnicos para mais informações.';
    default:
      return 'Não foi possível concluir a entrega. Nada foi alterado. '
          'Veja os detalhes técnicos para mais informações.';
  }
}

/// PROMPT 11.5.14 — texto técnico SEGURO para o painel de
/// `SeiConclusaoLoteStatus.conflitoDeIntegridade` (`sei_concluir_lote_dialog.dart`).
///
/// Causa do bug relatado: `SeiEscritaFalhouException.textoTecnico` inclui a
/// linha `Mensagem: ${mensagemErroConclusaoSei(...)}` — e o texto amigável
/// de `P0037` (acima) termina com "feche esta tela, releia o documento e
/// comece uma nova conclusão". Essa orientação foi escrita para uma recusa
/// DEFINITIVA e ISOLADA (P0037 recebido diretamente por um `confirmar()`
/// nunca antes tentado sob aquele `loteId`) — não para um
/// `conflitoDeIntegridade`, que só existe porque uma tentativa ANTERIOR
/// teve resultado desconhecido e continua CONGELADA: não é seguro sugerir
/// "comece uma nova conclusão" ali, e o aviso principal do próprio painel
/// já diz o oposto ("nenhuma ação automática é permitida"). Em vez de
/// alterar [mensagemErroConclusaoSei] (o que mudaria a mensagem também no
/// caso definitivo/isolado, homologado e coberto por teste — requisito 3
/// do PROMPT 11.5.14: não alterar regra já homologada sem necessidade),
/// este texto SUBSTITUI só a linha de mensagem por uma orientação segura,
/// reaproveitando o restante de [falha] (já sanitizado — nunca token,
/// credencial ou os parâmetros enviados, ver o comentário de
/// [SeiEscritaFalhouException]) e acrescentando o `loteId`, quando
/// conhecido, para facilitar a investigação (é só um identificador técnico
/// — UUID gerado no cliente — nunca um dado pessoal ou uma observação).
String textoTecnicoConflitoDeIntegridade(SeiEscritaFalhouException falha, {String? loteId}) {
  final linhas = <String>[
    'Operação: ${falha.operacao}',
    if (falha.codigo != null && falha.codigo!.isNotEmpty) 'Código: ${falha.codigo}',
    if (loteId != null && loteId.isNotEmpty) 'Identificador do lote (loteId): $loteId',
    'Mensagem: a tentativa original permanece preservada, sem nenhuma nova escrita — não inicie outra conclusão '
        'para este documento. Contate o suporte técnico com estes detalhes para investigar a divergência.',
    if (falha.detalhes != null && falha.detalhes!.isNotEmpty) 'Detalhes: ${falha.detalhes}',
    if (falha.dica != null && falha.dica!.isNotEmpty) 'Dica: ${falha.dica}',
  ];
  return linhas.join('\n');
}

/// Monta a falha tipada de uma recusa da RPC: mensagem amigável no
/// `message`, e o erro original do servidor (código/mensagem/detalhes/dica)
/// preservado para "Detalhes técnicos".
///
/// PROMPT 11.5.5 — [operacao] identifica QUAL RPC recusou, para o log e para
/// "Detalhes técnicos" (`SeiEscritaFalhouException.textoTecnico`); o mapeamento
/// de código→mensagem amigável ([mensagemErroConclusaoSei]) é o MESMO nos
/// dois casos, porque a RPC de lote propaga os códigos da individual sem
/// alteração. Default [operacaoConcluirItemSei] preserva o comportamento
/// anterior a este prompt para todo chamador existente.
SeiEscritaFalhouException falhaDeConclusaoSei({
  required String? codigo,
  required String mensagemDoServidor,
  String? detalhes,
  String? dica,
  Object? cause,
  String operacao = operacaoConcluirItemSei,
}) {
  final tecnico = [
    if (mensagemDoServidor.isNotEmpty) 'Servidor: $mensagemDoServidor',
    if (detalhes != null && detalhes.isNotEmpty) detalhes,
  ].join('\n');
  return SeiEscritaFalhouException(
    operacao: operacao,
    mensagem: mensagemErroConclusaoSei(codigo: codigo, mensagemDoServidor: mensagemDoServidor),
    codigo: codigo,
    detalhes: tecnico.isEmpty ? null : tecnico,
    dica: dica,
    cause: cause,
  );
}
