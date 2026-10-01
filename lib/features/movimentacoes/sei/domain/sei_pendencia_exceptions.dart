// Erros de negócio específicos de Documentos SEI pendentes — distintos de
// `AppException` genérica para a UI poder reagir de forma diferente (ex.:
// reler o documento e pedir para tentar de novo, em vez de só mostrar uma
// mensagem de erro).

import '../../../../core/errors/app_exception.dart';

/// A [versaoEsperada] enviada pelo cliente não bate mais com a versão
/// atual do documento: outra sessão editou, cancelou ou concluiu algo
/// entre a leitura e esta tentativa de escrita. A UI deve reler o
/// documento (nunca sobrescrever "por cima" da versão nova).
class SeiEdicaoConflitoException implements Exception {
  const SeiEdicaoConflitoException({required this.versaoEsperada, required this.versaoAtual});

  final int versaoEsperada;
  final int versaoAtual;

  @override
  String toString() =>
      'SeiEdicaoConflitoException: versão esperada $versaoEsperada, versão atual $versaoAtual — '
      'o documento foi alterado por outra sessão. Releia antes de tentar novamente.';
}

/// Tentativa de editar um documento que já tem ao menos um item concluído.
/// Nunca contornável pela UI; a base é a autoridade final.
class SeiDocumentoBloqueadoParaEdicaoException implements Exception {
  const SeiDocumentoBloqueadoParaEdicaoException(this.documentoId);

  final String documentoId;

  @override
  String toString() =>
      'SeiDocumentoBloqueadoParaEdicaoException: documento $documentoId tem item(ns) concluído(s) — '
      'edição de dados originais bloqueada permanentemente.';
}

/// Tentativa de cancelar/concluir um item que não está mais PENDENTE (ex.:
/// já foi concluído ou cancelado por outra sessão).
class SeiItemNaoElegivelException implements Exception {
  const SeiItemNaoElegivelException(this.itemId, this.statusAtual);

  final String itemId;
  final String statusAtual;

  @override
  String toString() => 'SeiItemNaoElegivelException: item $itemId está $statusAtual, não PENDENTE.';
}

/// `criar_documento_sei_pendente` recusou criar
/// porque já existe outro documento ATIVO (nenhum item cancelado sozinho
/// não conta) com o mesmo número SEI/processo, e a chamada não passou
/// `confirmarDuplicata: true`. Distinto do fluxo de aviso do
/// `SeiPendenciaSalvarController` (que já checa isso antes de chamar o
/// repositório): esta exceção cobre o caso em que a duplicata só passou a
/// existir DEPOIS daquela checagem — a corrida de "duas sessões salvando a
/// mesma pendência ao mesmo tempo" — e o banco, não o cliente, é
/// quem efetivamente barrou a segunda criação.
class SeiDocumentoDuplicadoException implements Exception {
  const SeiDocumentoDuplicadoException();

  @override
  String toString() => 'SeiDocumentoDuplicadoException: já existe um documento SEI pendente ativo com este número.';
}

/// `editar_documento_sei_pendente` valida CADA
/// item de `itensAlterados` (existe, pertence ao documento, está PENDENTE)
/// ANTES de aplicar qualquer correção. Qualquer item inválido rejeita a
/// operação INTEIRA: nenhuma correção parcial é aplicada, e os dados
/// anteriores do documento são preservados.
class SeiItemEdicaoInvalidaException implements Exception {
  const SeiItemEdicaoInvalidaException(this.itemId, this.motivo);

  final String itemId;
  final String motivo;

  @override
  String toString() => 'SeiItemEdicaoInvalidaException: item $itemId — $motivo';
}

/// a RPC de escrita (cancelar item / cancelar pendentes)
/// foi RECUSADA ou FALHOU no servidor (`PostgrestException`). Uma exceção da
/// RPC desfaz a transação inteira: nada foi alterado. Guarda o erro técnico
/// original ([codigo], [detalhes], [dica] e a mensagem) para diagnóstico.
/// Nunca contém token, credencial ou os parâmetros enviados.
class SeiEscritaFalhouException extends AppException {
  const SeiEscritaFalhouException({
    required this.operacao,
    required String mensagem,
    this.codigo,
    this.detalhes,
    this.dica,
    super.cause,
  }) : super(mensagem);

  /// Nome da função/operação que falhou (ex.: `cancelar_pendentes_documento_sei`).
  final String operacao;
  final String? codigo;
  final String? detalhes;
  final String? dica;

  /// Texto para diagnóstico (exibido em "Detalhes técnicos" e no log).
  String get textoTecnico {
    final linhas = <String>[
      'Operação: $operacao',
      if (codigo != null && codigo!.isNotEmpty) 'Código: $codigo',
      if (message.isNotEmpty) 'Mensagem: $message',
      if (detalhes != null && detalhes!.isNotEmpty) 'Detalhes: $detalhes',
      if (dica != null && dica!.isNotEmpty) 'Dica: $dica',
    ];
    return linhas.join('\n');
  }

  @override
  String toString() => 'SeiEscritaFalhouException($operacao, código: $codigo): $message';
}

/// a RPC de escrita retornou SUCESSO, mas o aplicativo
/// falhou DEPOIS, ao reler o documento. A escrita provavelmente foi
/// aplicada: repetir a ação às cegas seria arriscado. A UI deve pedir para
/// conferir o documento (e recarregar), nunca sugerir "tentar novamente".
class SeiEscritaConcluidaRecargaFalhouException implements Exception {
  const SeiEscritaConcluidaRecargaFalhouException({required this.operacao, required this.documentoId, this.cause});

  final String operacao;
  final String documentoId;
  final Object? cause;

  @override
  String toString() =>
      'SeiEscritaConcluidaRecargaFalhouException: $operacao concluída, mas a releitura do documento $documentoId falhou.';
}

/// `buscarLotePorId` encontrou um registro em
/// `documentos_sei_lotes_conclusao` para o `lote_id` consultado, mas a
/// identidade COMPLETA do registro (documento, itens, versão esperada,
/// observação, confirmação de limpeza ou usuário responsável) diverge dos
/// parâmetros que a decisão LOCAL enviaria.
///
/// NUNCA aceito silenciosamente como "o resultado desta decisão": é a
/// mesma situação que a RPC recusaria como `P0037` ao tentar ESCREVER com
/// este `lote_id`, só que detectada por LEITURA (sem `PostgrestException`).
/// `SeiConclusaoLoteController` trata isto como recusa definitiva.
class SeiReconciliacaoDivergenteException implements Exception {
  const SeiReconciliacaoDivergenteException(this.loteId, this.motivo);

  final String loteId;
  final String motivo;

  @override
  String toString() => 'SeiReconciliacaoDivergenteException: lote_id $loteId — $motivo';
}
