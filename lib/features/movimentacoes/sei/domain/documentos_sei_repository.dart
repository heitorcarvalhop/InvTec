import '../../domain/movimentacao.dart';
import 'documentos_sei_resultado.dart';
import 'sei_decisao_campo.dart';
import 'sei_conclusao_item_resultado.dart';
import 'sei_conclusao_lote_resultado.dart';
import 'sei_documento_pendente.dart';
import 'sei_evento_documento.dart';
import 'sei_item_pendencia_status.dart';

/// Acesso a Documentos SEI pendentes (PROMPT 11.3) — SEPARADO de
/// `MovimentacaoRepository`: nenhum método aqui grava em `movimentacoes`
/// nem chama `registrar_movimentacao`. Salvar/editar/cancelar uma pendência
/// nunca altera um patrimônio.
///
/// Nenhuma implementação real (`DocumentosSeiRepositorySupabase`) pode ser
/// exercida em produção nesta etapa: as tabelas que ela consulta só existem
/// depois que a migration proposta (`supabase/migrations/
/// 20260921090000_add_documentos_sei.sql`) for revisada e aplicada — o que
/// esta etapa NÃO faz. Testes usam exclusivamente um fake em memória.
abstract class DocumentosSeiRepository {
  /// Seção 4: lista paginada, com filtros por tipo/situação/documento/
  /// processo/patrimônio. A situação é sempre derivada dos itens no
  /// servidor (nunca uma coluna solta que possa divergir).
  Future<DocumentosSeiResultado> listar({
    int limit = 25,
    int offset = 0,
    MovimentacaoTipo? tipo,
    SeiItemPendenciaStatus? situacaoContemStatus,
    String? numeroDocumentoSei,
    String? numeroProcesso,
    String? numeroPatrimonio,
  });

  Future<SeiDocumentoPendente> obterPorId(String documentoId);

  Future<List<SeiEventoDocumento>> listarEventos(String documentoId);

  /// Seção 5 — checagem READ-ONLY antes de salvar: procura documentos já
  /// existentes com o MESMO número de documento SEI (e, se informado, o
  /// mesmo número de processo). Nunca usa o hash SHA-256 como critério de
  /// identidade (o mesmo despacho pode ser reexportado com bytes
  /// diferentes) e nunca bloqueia sozinha — só informa a UI, que exige
  /// confirmação explícita do usuário para prosseguir mesmo assim.
  Future<List<SeiDocumentoPendente>> buscarPossivelDuplicata({
    required String numeroDocumentoSei,
    String? numeroProcesso,
  });

  /// Cria a solicitação PENDENTE — nunca altera um patrimônio, nunca
  /// registra movimentação. Todo item nasce com status PENDENTE.
  ///
  /// PROMPT 11.3.1, seção 8: [confirmarDuplicata] espelha o parâmetro
  /// `p_confirmar_duplicata` da RPC — por padrão (`false`), a base recusa
  /// criar quando já existe outro documento ATIVO com o mesmo número
  /// SEI/processo (ver `SeiDocumentoDuplicadoException`). O
  /// `SeiPendenciaSalvarController` já faz essa checagem antes via
  /// [buscarPossivelDuplicata]; este parâmetro fecha a corrida "duas
  /// sessões salvando a mesma pendência ao mesmo tempo" — a segunda
  /// chamada pode encontrar a duplicata só no momento da escrita, não só
  /// na checagem prévia.
  Future<SeiDocumentoPendente> salvarRascunho(SeiDocumentoPendenteRascunho rascunho, {bool confirmarDuplicata = false});

  /// Seção 8/14 — só é aceito quando [versaoEsperada] ainda bate com a
  /// versão atual do documento E nenhum item está concluído (ver
  /// `SeiEdicaoConflitoException`/`SeiDocumentoBloqueadoParaEdicaoException`).
  /// [itensAlterados] é indexado por `SeiItemPendente.id`.
  Future<SeiDocumentoPendente> editarDocumento({
    required String documentoId,
    required int versaoEsperada,
    String? Function()? numeroDocumentoSei,
    String? Function()? numeroProcesso,
    String? Function()? numeroDocumentoFormatado,
    String? Function()? assunto,
    Map<String, SeiItemPendenteEdicao> itensAlterados = const {},
    required String motivo,
  });

  /// Seção 9/10 — cancela UM item PENDENTE (nunca um já concluído/
  /// cancelado: ver `SeiItemNaoElegivelException`). Não exige que o
  /// documento inteiro esteja desbloqueado para edição: cancelar itens
  /// pendentes continua possível mesmo depois da primeira conclusão.
  Future<SeiDocumentoPendente> cancelarItem({required String itemId, required String motivo});

  /// Seção 9/10 — cancela TODOS os itens ainda PENDENTES do documento
  /// (nunca toca itens já concluídos ou já cancelados). É a operação por
  /// trás de "Cancelar documento": um cancelamento parcial NUNCA desfaz
  /// conclusões anteriores.
  Future<SeiDocumentoPendente> cancelarPendentesDoDocumento({required String documentoId, required String motivo});

  /// PROMPT 11.4.3 — conclui a ENTREGA de UM item PENDENTE: cria a
  /// movimentação patrimonial real, atualiza o patrimônio, vincula
  /// `movimentacao_id` ao item, marca-o CONCLUIDO e grava o evento
  /// ITEM_CONCLUIDO — TUDO em uma única transação, na RPC
  /// `concluir_item_documento_sei`. O cliente NUNCA chama
  /// `registrar_movimentacao` diretamente.
  ///
  ///  * [versaoEsperada] é obrigatório: se o documento mudou desde a leitura
  ///    (edição/cancelamento/conclusão de outra pessoa), a conclusão é
  ///    recusada (`P0010`).
  ///  * [confirmarLimpezaDestino] só deve ser `true` quando o usuário
  ///    confirmou, na tela, que a conclusão apagará a localização e/ou o
  ///    responsável atuais do patrimônio (`P0035` sem isso).
  ///  * Repetição de um item já concluído NÃO é erro: devolve o estado
  ///    existente com [SeiConclusaoItemResultado.jaConcluido] `true`.
  ///
  /// Recusas da RPC viram `SeiEscritaFalhouException` (mensagem amigável +
  /// erro original em "detalhes técnicos").
  Future<SeiConclusaoItemResultado> concluirItem({
    required String documentoId,
    required String itemId,
    required int versaoEsperada,
    String? observacao,
    bool confirmarLimpezaDestino = false,
  });

  /// PROMPT 11.5.5 — conclui a ENTREGA de VÁRIOS itens PENDENTES de UM MESMO
  /// documento, de forma atômica (tudo ou nada), via a RPC
  /// `concluir_itens_documento_sei_lote` — que, por dentro, chama
  /// `concluir_item_documento_sei` uma vez por item, na MESMA transação (ver
  /// `supabase/migrations/20260928100000_add_concluir_itens_documento_sei_lote.sql`).
  /// O cliente NUNCA laça chamadas à RPC individual: esta é UMA ÚNICA
  /// chamada de rede, para UM único documento por vez (nunca lote entre
  /// documentos diferentes).
  ///
  ///  * [loteId] é OBRIGATÓRIO e gerado pelo CHAMADOR (a UI), uma única vez
  ///    por decisão confirmada — o repositório NUNCA gera um UUID sozinho.
  ///    Reenviar a MESMA chamada com o MESMO [loteId] e os MESMOS demais
  ///    parâmetros (idênticos, campo a campo) é um retry seguro: devolve o
  ///    resultado já registrado, sem travar nem escrever nada de novo
  ///    ([SeiConclusaoLoteResultado.jaExecutado] `true`). O MESMO [loteId]
  ///    com QUALQUER parâmetro diferente é recusado (`P0037`) — nunca
  ///    reaproveitado silenciosamente para uma operação diferente.
  ///  * [versaoEsperada] é a versão do documento ANTES do primeiro item do
  ///    lote (mesmo papel de [concluirItem]): se o documento mudou desde a
  ///    leitura, a chamada inteira é recusada (`P0010`), nenhum item é
  ///    concluído.
  ///  * [confirmarLimpezaDestino] é UMA ÚNICA flag para o lote inteiro
  ///    (repassada, sem alteração, a cada item — a decisão de limpar ou não
  ///    continua sendo avaliada item a item por `concluir_item_documento_sei`,
  ///    exatamente como na conclusão individual).
  ///  * Se algum item de [itemIds] não estiver mais PENDENTE no momento da
  ///    chamada (concluído ou cancelado por outra operação, individual ou de
  ///    outro lote), a chamada INTEIRA é recusada (`P0036`) — nunca conclui
  ///    só o restante.
  ///  * Máximo de 200 itens por chamada; o mesmo patrimônio não pode
  ///    aparecer duas vezes no mesmo lote (`P0001` nos dois casos).
  ///
  /// Recusas da RPC viram `SeiEscritaFalhouException` (mesma exceção tipada
  /// de [concluirItem] — mensagem amigável + erro original em "detalhes
  /// técnicos").
  Future<SeiConclusaoLoteResultado> concluirItensLote({
    required String documentoId,
    required List<String> itemIds,
    required int versaoEsperada,
    required String loteId,
    String? observacao,
    bool confirmarLimpezaDestino = false,
  });

  /// PROMPT 11.5.6/11.5.6.1 — reconciliação de um `loteId` cuja chamada a
  /// [concluirItensLote] terminou com RESULTADO DESCONHECIDO (timeout,
  /// falha de conexão): lê diretamente `documentos_sei_lotes_conclusao`
  /// (SELECT simples, sem RPC — a tabela só é ESCRITA pela função SECURITY
  /// DEFINER; a leitura respeita a RLS de `authenticated` já instalada na
  /// migration `20260928100000_add_concluir_itens_documento_sei_lote.sql`,
  /// seção 1).
  ///
  /// [documentoId], [itemIds], [versaoEsperada], [observacao] e
  /// [confirmarLimpezaDestino] são os MESMOS parâmetros que a decisão LOCAL
  /// enviaria a [concluirItensLote] — usados para conferir a IDENTIDADE
  /// COMPLETA do registro encontrado, nunca só o `loteId`: um `lote_id`
  /// batendo sozinho NUNCA é aceito como prova de que o registro pertence a
  /// esta decisão (o sexto campo de identidade, o usuário responsável, é
  /// conferido pela implementação contra a sessão autenticada ATUAL — não
  /// recebido aqui, pelo mesmo motivo que a RPC usa `auth.uid()`, não um
  /// parâmetro do cliente).
  ///
  /// Devolve:
  ///  * `null` — nenhum registro para este `loteId`: a chamada REALMENTE não
  ///    foi aplicada (a homologação 11.5.3 comprovou que qualquer exceção
  ///    desfaz TUDO, sem resíduo) — um retry com o MESMO payload continua
  ///    seguro. A ausência momentânea não é, por si só, prova definitiva
  ///    contra uma corrida (ex.: a escrita ainda não commitou do lado do
  ///    servidor no instante exato desta leitura) — por isso o chamador
  ///    nunca deve tratar `null` como permissão para começar uma decisão
  ///    NOVA automaticamente, só para permitir `retry`/nova consulta.
  ///  * o [SeiConclusaoLoteResultado] registrado — a chamada FOI aplicada
  ///    com sucesso (por esta tentativa ou por uma anterior que também deu
  ///    timeout do lado do cliente, mas chegou ao servidor) E a identidade
  ///    do registro bate com os parâmetros informados; nenhuma nova escrita
  ///    deve ser tentada com este `loteId`.
  ///
  /// Lança [SeiReconciliacaoDivergenteException] quando o registro EXISTE
  /// mas a identidade diverge — erro de integridade, nunca absorvido
  /// silenciosamente. Uma falha de leitura (rede/permissão) propaga a
  /// exceção original (nunca convertida em `null`): o chamador não pode
  /// confundir "não consegui perguntar" com "perguntei e não achei".
  Future<SeiConclusaoLoteResultado?> buscarLotePorId({
    required String loteId,
    required String documentoId,
    required List<String> itemIds,
    required int versaoEsperada,
    String? observacao,
    required bool confirmarLimpezaDestino,
  });
}

/// Alteração de um único item dentro de uma edição de documento (seção 13)
/// — cada campo TEXTUAL extraído do PDF usa a função de correção (não o
/// valor bruto), para o repositório sempre preservar
/// [SeiValorCorrigivel.original] e registrar quem/quando/por quê. Nunca
/// inclui origem: por design (mesma regra de `registrar_movimentacao`), a
/// origem sempre vem do estado atual do InvTec, nunca de texto corrigido
/// manualmente.
///
/// PROMPT 11.3.1, seção 3: destino/localização/responsável são valores
/// RESOLVIDOS (não têm par original/corrigido) — usam `Function()?`/enum
/// direto, e [decisaoLocalizacao]/[localizacaoDestinoId] (e o par
/// responsável) sempre precisam ser enviados JUNTOS, coerentes, para nunca
/// violar as constraints de coerência da migration (ex.: `DEFINIDO` sem
/// localização, ou `CONFIRMADO_SEM_INFORMACAO` com uma localização
/// presente).
class SeiItemPendenteEdicao {
  const SeiItemPendenteEdicao({
    this.numeroPatrimonioCorrigido,
    this.destinoTextoCorrigido,
    this.numeroChamadoCorrigido,
    this.equipamentoTextoCorrigido,
    this.destinoSetorId,
    this.localizacaoDestinoId,
    this.decisaoLocalizacao,
    this.responsavelDestino,
    this.decisaoResponsavel,
  });

  final String? numeroPatrimonioCorrigido;
  final String? destinoTextoCorrigido;
  final String? numeroChamadoCorrigido;
  final String? equipamentoTextoCorrigido;

  final String? Function()? destinoSetorId;
  final String? Function()? localizacaoDestinoId;
  final SeiDecisaoCampo? decisaoLocalizacao;
  final String? Function()? responsavelDestino;
  final SeiDecisaoCampo? decisaoResponsavel;

  bool get vazia =>
      numeroPatrimonioCorrigido == null &&
      destinoTextoCorrigido == null &&
      numeroChamadoCorrigido == null &&
      equipamentoTextoCorrigido == null &&
      destinoSetorId == null &&
      localizacaoDestinoId == null &&
      decisaoLocalizacao == null &&
      responsavelDestino == null &&
      decisaoResponsavel == null;
}
