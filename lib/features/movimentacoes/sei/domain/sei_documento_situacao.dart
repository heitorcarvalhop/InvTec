import 'sei_item_pendencia_status.dart';

/// Situação GERAL de um documento pendente (PROMPT 11.3, seção 7) — sempre
/// DERIVADA dos status dos itens, nunca um campo gravado independentemente
/// (evita estado contraditório entre a situação exibida e os itens reais).
/// A mesma lógica de [calcularSituacaoDocumento] é reproduzida em SQL, como
/// função/view (nunca uma coluna gravável), na migration proposta — ver
/// `documentos_sei_situacao`.
enum SeiDocumentoSituacao {
  /// Nenhum item foi concluído ou cancelado ainda (inclui documento sem
  /// nenhum item, ainda que este caso não deva ocorrer na prática).
  pendente,

  /// Há pelo menos um item concluído OU cancelado, e ainda há pelo menos um
  /// item pendente.
  parcialmenteConcluido,

  /// Todos os itens estão concluídos.
  concluido,

  /// Todos os itens estão cancelados (nenhuma conclusão).
  cancelado,

  /// Não há mais nenhum item pendente, mas os itens concluídos e cancelados
  /// coexistem (parte foi entregue, o restante foi cancelado).
  encerradoParcialmente,
}

/// Espelha os valores textuais que a coluna `situacao` da view
/// `documentos_sei_com_situacao` devolve (PROMPT 11.3.5.3) — usado ao ler
/// uma linha de LISTAGEM (a view já manda a situação pronta; ver
/// [calcularSituacaoDocumento] para quando os itens estão carregados e a
/// situação é derivada localmente).
SeiDocumentoSituacao situacaoDocumentoFromValue(String value) {
  switch (value) {
    case 'PENDENTE':
      return SeiDocumentoSituacao.pendente;
    case 'PARCIALMENTE_CONCLUIDO':
      return SeiDocumentoSituacao.parcialmenteConcluido;
    case 'CONCLUIDO':
      return SeiDocumentoSituacao.concluido;
    case 'CANCELADO':
      return SeiDocumentoSituacao.cancelado;
    case 'ENCERRADO_PARCIALMENTE':
      return SeiDocumentoSituacao.encerradoParcialmente;
    default:
      throw ArgumentError('Situação de documento SEI inválida: $value');
  }
}

extension SeiDocumentoSituacaoLabel on SeiDocumentoSituacao {
  String get label {
    switch (this) {
      case SeiDocumentoSituacao.pendente:
        return 'Pendente';
      case SeiDocumentoSituacao.parcialmenteConcluido:
        return 'Parcialmente concluído';
      case SeiDocumentoSituacao.concluido:
        return 'Concluído';
      case SeiDocumentoSituacao.cancelado:
        return 'Cancelado';
      case SeiDocumentoSituacao.encerradoParcialmente:
        return 'Encerrado parcialmente';
    }
  }
}

/// Deriva a situação geral a partir do status de cada item — função pura,
/// sem estados contraditórios possíveis (PROMPT 11.3, seção 7). Uma lista
/// vazia é tratada como [SeiDocumentoSituacao.pendente] (documento recém
/// criado, ainda sem itens carregados na leitura atual).
///
/// PROMPT 11.3.2, seção 2 — auditoria encontrou um caso classificado
/// errado: 0 concluídos + itens pendentes + itens cancelados caía no
/// `return parcialmenteConcluido` final porque nenhum `if` anterior cobria
/// "ainda há pendente, mas nada foi concluído" separado de "ainda há
/// pendente E algo foi concluído" — mas [SeiDocumentoSituacao.
/// parcialmenteConcluido] exige, pelo próprio nome, ao menos UMA conclusão
/// real; sem nenhuma movimentação efetiva, o documento continua
/// simplesmente pendente, não importa quantos itens já foram cancelados.
/// Mesma lógica mantida em espelho na view SQL `documentos_sei_com_situacao`
/// da migration proposta — qualquer mudança aqui precisa ser replicada lá.
SeiDocumentoSituacao calcularSituacaoDocumento(List<SeiItemPendenciaStatus> statusItens) {
  if (statusItens.isEmpty) return SeiDocumentoSituacao.pendente;

  var pendentes = 0;
  var concluidos = 0;
  var cancelados = 0;
  for (final status in statusItens) {
    switch (status) {
      case SeiItemPendenciaStatus.pendente:
        pendentes++;
      case SeiItemPendenciaStatus.concluido:
        concluidos++;
      case SeiItemPendenciaStatus.cancelado:
        cancelados++;
    }
  }

  if (concluidos == 0 && pendentes > 0) return SeiDocumentoSituacao.pendente;
  if (concluidos == statusItens.length) return SeiDocumentoSituacao.concluido;
  if (cancelados == statusItens.length) return SeiDocumentoSituacao.cancelado;
  if (pendentes == 0) return SeiDocumentoSituacao.encerradoParcialmente;
  return SeiDocumentoSituacao.parcialmenteConcluido;
}
