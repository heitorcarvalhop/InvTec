import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/uuid_v4.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../application/sei_conclusao_erros.dart';
import '../data/documentos_sei_repository_supabase.dart';
import '../domain/sei_conclusao_lote_resultado.dart';
import '../domain/sei_pendencia_exceptions.dart';

/// PROMPT 11.5.6 — estágio da decisão de conclusão em lote CONGELADA neste
/// controller. Ver [SeiConclusaoLoteState] para o que cada um implica sobre
/// o que pode ser chamado a seguir.
enum SeiConclusaoLoteStatus {
  /// Nenhuma decisão em andamento: [confirmar] pode ser chamado.
  ocioso,

  /// Chamada em voo (`concluirItensLote` ou `buscarLotePorId`) — QUALQUER
  /// novo clique em [confirmar]/[retry]/[reconciliar] é ignorado (nunca
  /// dispara uma segunda chamada concorrente).
  executando,

  /// A RPC confirmou (nova conclusão OU retry idêntico/`ja_executado`) —
  /// [resultado] preenchido. A decisão está ENCERRADA: [reiniciar] é
  /// necessário antes de qualquer nova [confirmar].
  sucesso,

  /// O SERVIDOR recusou explicitamente (`SeiEscritaFalhouException` — inclui
  /// P0010, P0036, P0037 e qualquer outro código): a transação foi desfeita,
  /// NADA foi escrito. A decisão está ENCERRADA (nunca reenviada sozinha) —
  /// [falha] preenchido; [reiniciar] é necessário antes de uma NOVA decisão
  /// (com dados relidos, quando o código pedir — ver o comentário de
  /// [confirmar]).
  recusado,

  /// A chamada terminou sem confirmação nem recusa clara do servidor
  /// (timeout, falha de conexão, qualquer exceção que não seja
  /// `SeiEscritaFalhouException`) — o RESULTADO REAL é desconhecido: pode
  /// ter chegado ao servidor e sido aplicado, ou não. A decisão PERMANECE
  /// CONGELADA ([decisao] não muda): só [retry] (reenvia o MESMO payload) ou
  /// [reconciliar] (consulta `documentos_sei_lotes_conclusao` pelo
  /// `loteId`) são permitidos a partir daqui — nunca [confirmar] com uma
  /// seleção nova enquanto este estado persistir.
  resultadoDesconhecido,

  /// PROMPT 11.5.6.2 — [reconciliar] encontrou, para o `loteId` CONGELADO
  /// desta decisão, um registro em `documentos_sei_lotes_conclusao` cuja
  /// identidade DIVERGE dos parâmetros que esta decisão enviaria
  /// ([SeiReconciliacaoDivergenteException]). DIFERENTE de
  /// [SeiConclusaoLoteStatus.recusado]: isto NÃO é uma recusa síncrona e
  /// confiável do SERVIDOR (nenhuma escrita foi tentada — é uma leitura
  /// comparada no cliente), então não há garantia equivalente de que "nada
  /// foi escrito por esta decisão". Um conflito assim exige INVESTIGAÇÃO —
  /// nunca é resolvido automaticamente por este controller:
  ///  * [decisao] (`loteId` e os seis parâmetros) e [falha] (o motivo
  ///    técnico do conflito) permanecem CONGELADOS, para diagnóstico;
  ///  * [retry] e [reconciliar] são IGNORADOS a partir daqui (nunca reenvia
  ///    a RPC nem consulta de novo sozinho);
  ///  * [reiniciar] também é IGNORADO — nenhuma decisão nova pode ser
  ///    criada automaticamente por cima de um conflito não resolvido.
  /// A única saída deste estado, nesta etapa, é fora deste controller
  /// (investigação manual/suporte — nenhum método aqui o resolve; ver o
  /// comentário de escopo no topo da classe).
  conflitoDeIntegridade,
}

/// Os SEIS campos da decisão de lote CONGELADOS no momento da confirmação
/// (PROMPT 11.5.6, seção 3) — imutáveis depois de criados. [itemIds] já
/// chega CANÔNICO (distinto, ordenado): a mesma forma que
/// `concluir_itens_documento_sei_lote` produziria internamente, para a
/// comparação de identidade de um retry nunca depender da ordem em que o
/// usuário clicou nos itens.
class SeiDecisaoLoteConfirmada {
  SeiDecisaoLoteConfirmada({
    required this.documentoId,
    required List<String> itemIds,
    required this.versaoEsperada,
    required this.loteId,
    this.observacao,
    required this.confirmarLimpezaDestino,
  }) : itemIds = List.unmodifiable({...itemIds}.toList()..sort());

  final String documentoId;
  final List<String> itemIds;
  final int versaoEsperada;

  /// Gerado UMA ÚNICA VEZ por decisão confirmada (ver
  /// `SeiConclusaoLoteController.confirmar`) — o repositório NUNCA gera um
  /// `loteId` sozinho (PROMPT 11.5.5, restrição preservada aqui).
  final String loteId;
  final String? observacao;
  final bool confirmarLimpezaDestino;
}

class SeiConclusaoLoteState {
  const SeiConclusaoLoteState({this.status = SeiConclusaoLoteStatus.ocioso, this.decisao, this.resultado, this.falha});

  final SeiConclusaoLoteStatus status;
  final SeiDecisaoLoteConfirmada? decisao;
  final SeiConclusaoLoteResultado? resultado;
  final SeiEscritaFalhouException? falha;

  /// Há uma tentativa NÃO RESOLVIDA — resultado desconhecido OU conflito de
  /// integridade — esperando ação (ou investigação manual, no caso do
  /// conflito). Enquanto isto for `true`, [confirmar] e [reiniciar] não
  /// têm efeito. Sobrevive a fechar/reabrir qualquer diálogo visual
  /// enquanto ESTE controller (o provider que o expõe) continuar vivo —
  /// nenhuma persistência em disco: reiniciar o aplicativo perde esta
  /// informação (ver o comentário no topo do arquivo).
  bool get temTentativaPendente =>
      (status == SeiConclusaoLoteStatus.resultadoDesconhecido || status == SeiConclusaoLoteStatus.conflitoDeIntegridade) &&
      decisao != null;

  /// PROMPT 11.5.6.2 — `true` só no estado de conflito de integridade
  /// (ver [SeiConclusaoLoteStatus.conflitoDeIntegridade]): nem [retry] nem
  /// [reconciliar] têm efeito a partir daqui (diferente de um
  /// [SeiConclusaoLoteStatus.resultadoDesconhecido] comum, onde os dois
  /// continuam permitidos) — a futura UI deve usar isto para nunca oferecer
  /// os botões normais de "tentar novamente"/"consultar de novo" neste
  /// caso, e sim uma indicação de que o caso exige suporte/investigação.
  bool get emConflitoDeIntegridade => status == SeiConclusaoLoteStatus.conflitoDeIntegridade;

  bool get executando => status == SeiConclusaoLoteStatus.executando;
}

/// PROMPT 11.5.6 — controlador/estado de aplicação da conclusão em lote:
/// congela a decisão confirmada, gera o `loteId` uma única vez, impede
/// chamadas concorrentes e implementa o retry seguro sobre resultado
/// desconhecido (incluindo a reconciliação contra
/// `documentos_sei_lotes_conclusao`). NÃO constrói NENHUMA interface — é
/// puro estado + orquestração de chamadas ao [DocumentosSeiRepository],
/// testável sem `pumpWidget` (mesmo padrão de `SeiPendenciaSalvarController`
/// — ver `sei_pendencia_salvar_controller.dart`).
///
/// PROIBIDO NESTE PROMPT: nenhuma UI, nenhuma seleção múltipla widget,
/// nenhuma alteração da conclusão individual ou das RPCs.
///
/// LIMITAÇÃO DOCUMENTADA (PROMPT 11.5.6, restrição explícita): este estado
/// vive só em memória, no processo do app — fechar e reabrir um DIÁLOGO
/// preserva a tentativa pendente (o provider, sem `.autoDispose`,
/// continua vivo), mas FECHAR O APLICATIVO a perde. Não há persistência em
/// disco/`shared_preferences` nesta etapa: se o app for encerrado com uma
/// tentativa de resultado desconhecido em aberto, a única forma de saber o
/// que aconteceu depois de reabrir é reler o documento (`obterPorId`) e
/// observar o status dos itens — o `loteId` daquela tentativa específica
/// se perde, mas os itens já concluídos no servidor aparecem concluídos.
///
/// ISOLAMENTO (PROMPT 11.5.6.1):
///  * ENTRE DOCUMENTOS — este é um único provider GLOBAL (não `.family` por
///    documento): enquanto houver uma [SeiConclusaoLoteState.temTentativaPendente]
///    para o Documento A, [confirmar] é IGNORADO para qualquer outro
///    documento (nunca "troca" silenciosamente de decisão) — o chamador
///    precisa resolver a pendência do Documento A primeiro. Não é uma
///    limitação: é a mesma garantia "nenhuma chamada concorrente" aplicada
///    entre documentos, não só dentro do mesmo.
///  * ENTRE SESSÕES — [build] observa [authControllerProvider] só para ser
///    RECRIADO (nenhuma leitura do valor em si) a cada mudança de sessão
///    (login, logout, troca de usuário, expiração): qualquer decisão
///    pendente é DESCARTADA do estado do cliente nesse instante — nunca
///    reaproveitada por uma sessão diferente daquela que a confirmou. Isto
///    NÃO apaga o registro no servidor: se o mesmo usuário original logar de
///    novo, `documentos_sei_lotes_conclusao` continua lá (consultável por
///    `obterPorId`/histórico), só o estado local da tentativa é que se
///    perde — mesma limitação de "sem persistência em disco" do parágrafo
///    acima. Como defesa adicional (não só cosmética), a própria RPC e esta
///    reconciliação conferem `criado_por`/`auth.uid()` contra a sessão
///    ATUAL (ver [buscarLotePorId] e a checagem de identidade em
///    [DocumentosSeiRepository.buscarLotePorId]): mesmo que o estado local
///    sobrevivesse por algum bug, uma tentativa de reenviar/reconciliar sob
///    outro usuário seria recusada, nunca aceita silenciosamente.
///  * REINICIALIZAÇÃO DO APLICATIVO — mesmo efeito de uma troca de sessão:
///    estado em memória, perdido. Nenhuma persistência permanente foi
///    criada nesta etapa (fora de escopo do PROMPT 11.5.6.1).
final seiConclusaoLoteControllerProvider = NotifierProvider<SeiConclusaoLoteController, SeiConclusaoLoteState>(
  SeiConclusaoLoteController.new,
);

class SeiConclusaoLoteController extends Notifier<SeiConclusaoLoteState> {
  /// [gerarLoteId] é injetável só para teste (geração determinística); em
  /// produção, sempre [gerarUuidV4] (UUID v4 aleatório, gerado no cliente —
  /// ver `core/utils/uuid_v4.dart`).
  SeiConclusaoLoteController({String Function()? gerarLoteId}) : _gerarLoteId = gerarLoteId ?? gerarUuidV4;

  final String Function() _gerarLoteId;

  /// PROMPT 11.5.6.1 — id do usuário (`Profile.id`, que corresponde a
  /// `auth.uid()`) da última resolução CONHECIDA de `authControllerProvider`
  /// — usado só para comparar em [build] e nunca lido diretamente por
  /// [confirmar]/[retry]/[reconciliar] (a identidade real do usuário para a
  /// escrita/leitura em si é sempre a sessão ATUAL, resolvida pelo
  /// repositório na hora da chamada, nunca este valor capturado).
  String? _usuarioConhecido;

  @override
  SeiConclusaoLoteState build() {
    // PROMPT 11.5.6.1 — isolamento entre sessões, SEM destruir o estado à
    // toa: `ref.watch(authControllerProvider)` faria este `build()` rodar de
    // novo a CADA transição assíncrona do provider de auth — inclusive
    // `loading`->`data` do MESMO usuário (ex.: um refresh trivial de
    // perfil) — apagando uma decisão em andamento sem nenhuma troca real de
    // sessão. `ref.listen` evita isso: o notifier NÃO é reconstruído; só
    // reage (`state = ...`) quando o usuário AUTENTICADO RESOLVIDO
    // realmente muda de valor (login, logout ou troca de usuário) —
    // ignorando estados transitórios de carregamento/erro sem valor.
    _usuarioConhecido = ref.read(authControllerProvider).value?.profile?.id;
    ref.listen(authControllerProvider, (previous, next) {
      if (!next.hasValue) return; // carregando/erro sem valor — nada a comparar ainda
      final novoUsuario = next.value?.profile?.id;
      if (novoUsuario == _usuarioConhecido) return; // mesmo usuário (ou segue deslogado)
      _usuarioConhecido = novoUsuario;
      state = const SeiConclusaoLoteState();
    });
    return const SeiConclusaoLoteState();
  }

  /// Confirma uma NOVA decisão de lote: gera o `loteId` UMA ÚNICA VEZ,
  /// congela os seis parâmetros e dispara a chamada. Ignorado (sem efeito)
  /// se já houver uma chamada em andamento ([SeiConclusaoLoteState.executando])
  /// OU uma tentativa pendente de reconciliação
  /// ([SeiConclusaoLoteState.temTentativaPendente]) — o chamador precisa
  /// [retry]/[reconciliar]/[reiniciar] essa tentativa primeiro; nunca duas
  /// decisões concorrentes para o mesmo documento.
  ///
  /// Depois de um [SeiConclusaoLoteStatus.recusado] com `P0010` ou `P0036`,
  /// o chamador deve reler o documento (`obterPorId`), atualizar a seleção/
  /// dados exibidos e só então chamar [reiniciar] seguido de um NOVO
  /// [confirmar] — nunca reenviar os mesmos `itemIds`/`versaoEsperada` sem
  /// reler. Depois de `P0037`, nunca reenviar automaticamente com
  /// parâmetros divergentes: o `loteId` daquela tentativa está
  /// permanentemente associado a OUTRA operação.
  Future<void> confirmar({
    required String documentoId,
    required List<String> itemIds,
    required int versaoEsperada,
    String? observacao,
    required bool confirmarLimpezaDestino,
  }) async {
    if (state.executando || state.temTentativaPendente) return;
    final decisao = SeiDecisaoLoteConfirmada(
      documentoId: documentoId,
      itemIds: itemIds,
      versaoEsperada: versaoEsperada,
      loteId: _gerarLoteId(),
      observacao: observacao,
      confirmarLimpezaDestino: confirmarLimpezaDestino,
    );
    await _executar(decisao);
  }

  /// Reenvia a MESMA decisão congelada (mesmo `loteId`, mesmos seis
  /// parâmetros — nunca aceita parâmetros novos) — só tem efeito quando o
  /// status é EXATAMENTE [SeiConclusaoLoteStatus.resultadoDesconhecido].
  /// Ignorado (sem efeito) se já estiver executando, se não houver nada
  /// pendente, ou se a tentativa já estiver marcada como
  /// [SeiConclusaoLoteStatus.conflitoDeIntegridade] (PROMPT 11.5.6.2 —
  /// nenhum retry automático depois de uma divergência de reconciliação:
  /// aquele `loteId` já se mostrou não confiável, reenviá-lo sozinho não é
  /// seguro).
  Future<void> retry() async {
    final decisao = state.decisao;
    if (state.executando || decisao == null) return;
    if (state.status != SeiConclusaoLoteStatus.resultadoDesconhecido) return;
    // PROMPT 11.5.8 — `verificarAntesDeRecusar: true`: ver o comentário de
    // [_resolverRecusaDeRetry] para o porquê de um retry NUNCA aceitar uma
    // `SeiEscritaFalhouException` como recusa definitiva sem antes conferir
    // `documentos_sei_lotes_conclusao` — diferente de [confirmar], onde a
    // PRIMEIRA tentativa sob um `loteId` recém-gerado não tem nenhuma
    // tentativa anterior com a qual uma recusa possa ser confundida.
    await _executar(decisao, verificarAntesDeRecusar: true);
  }

  Future<void> _executar(SeiDecisaoLoteConfirmada decisao, {bool verificarAntesDeRecusar = false}) async {
    state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.executando, decisao: decisao);
    try {
      final resultado = await ref
          .read(documentosSeiRepositoryProvider)
          .concluirItensLote(
            documentoId: decisao.documentoId,
            itemIds: decisao.itemIds,
            versaoEsperada: decisao.versaoEsperada,
            loteId: decisao.loteId,
            observacao: decisao.observacao,
            confirmarLimpezaDestino: decisao.confirmarLimpezaDestino,
          );
      state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.sucesso, decisao: decisao, resultado: resultado);
    } on SeiEscritaFalhouException catch (falha) {
      // Recusa DEFINITIVA do servidor: a homologação 11.5.3 comprovou que
      // qualquer exceção desfaz a transação inteira, sem resíduo — nada foi
      // escrito POR ESTA CHAMADA. Vale para P0010/P0036/P0037 e qualquer
      // outro código propagado da RPC individual (P0030-P0035, P0002,
      // P0001, 42501).
      //
      // PROMPT 11.5.8 — mas isso NÃO é o mesmo que provar que a TENTATIVA
      // ORIGINAL (a que gerou o resultado desconhecido, antes deste retry)
      // não foi aplicada: `concluir_itens_documento_sei_lote` confere a
      // permissão do usuário (42501) ANTES de consultar `p_lote_id` em
      // `documentos_sei_lotes_conclusao` (migration
      // 20260928100000_add_concluir_itens_documento_sei_lote.sql, passos 1
      // e 4-6) — um retry pode receber 42501 puramente porque a permissão
      // do usuário mudou ENTRE as duas chamadas, mesmo que a tentativa
      // original já tenha sido aplicada com sucesso sob este MESMO
      // `loteId`. Por isso, só quando [verificarAntesDeRecusar] for `true`
      // (ou seja, esta chamada é um [retry], nunca a primeira tentativa de
      // [confirmar]) esta recusa é confirmada por leitura direta antes de
      // ser aceita.
      if (verificarAntesDeRecusar) {
        await _resolverRecusaDeRetry(decisao, falha);
      } else {
        state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.recusado, decisao: decisao, falha: falha);
      }
    } catch (_) {
      // Resultado DESCONHECIDO (rede/timeout/qualquer coisa que não seja
      // uma recusa clara do servidor) — a decisão continua CONGELADA para
      // `retry`/`reconciliar`; NUNCA presumida como "falhou no servidor".
      state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.resultadoDesconhecido, decisao: decisao);
    }
  }

  /// PROMPT 11.5.8.1/11.5.8.2 — códigos cuja checagem, na RPC real
  /// (`concluir_itens_documento_sei_lote`, migration
  /// 20260928100000_add_concluir_itens_documento_sei_lote.sql), só roda
  /// DEPOIS que o `lote_id` já foi consultado (passos 4-6) e NADA foi
  /// encontrado: P0036 (passo 8) e P0010 (passo 10). Só para ESTES códigos
  /// um `buscarLotePorId` que devolve `null` é aceito como PROVA de que
  /// nada foi escrito sob este `loteId` — qualquer outro código NUNCA tem
  /// essa garantia:
  ///  * `42501` — checagem de permissão, passo 1, ANTES do lookup do
  ///    `loteId`: um `null` pode significar "não existe" OU "existe, mas a
  ///    RLS da sessão ATUAL não deixa enxergar"
  ///    (`documentos_sei_lotes_conclusao_select` exige
  ///    `has_perfil('ADMIN','GESTOR','OPERADOR','CONSULTA')`) — se a
  ///    permissão mudou entre o retry e esta leitura, a linha pode estar lá
  ///    e ainda assim vir `null` (ver [_resolverRecusaDeRetry]);
  ///  * `P0037` NÃO ENTRA NESTA LISTA — PROMPT 11.5.8.2 corrigiu uma
  ///    classificação errada de 11.5.8/11.5.8.1 (que tratava P0037 como
  ///    mais um código de ausência): diferente de P0010/P0036, P0037 só é
  ///    lançado (passos 4-6) quando `v_lote` FOI ENCONTRADO e algum dos 6
  ///    campos de identidade (ou `criado_por`) diverge — nunca por
  ///    ausência. Um retry recebendo P0037 já É, por si só, a RPC
  ///    confirmando de forma SÍNCRONA que existe um registro divergente
  ///    para este `loteId` — tratado à parte em [_resolverRecusaDeRetry]
  ///    (nunca aceito como prova de ausência, mesmo que a leitura de
  ///    verificação devolva `null`).
  static const _codigosRecusaConfirmadosPorAusencia = {'P0010', 'P0036'};

  /// PROMPT 11.5.8/11.5.8.1/11.5.8.2 — só chamado a partir de um [retry] que
  /// recebeu uma [SeiEscritaFalhouException]. Confere
  /// `documentos_sei_lotes_conclusao` pelo `loteId` CONGELADO antes de
  /// aceitar a recusa como definitiva — mesma leitura de [reconciliar].
  /// Desfechos, nunca colapsados:
  ///  1. registro encontrado E idêntico → a tentativa ORIGINAL (ou esta) na
  ///     verdade FOI aplicada → [SeiConclusaoLoteStatus.sucesso] — a recusa
  ///     recebida agora NUNCA é apresentada ao usuário (vale para QUALQUER
  ///     código, P0037 incluído: um match idêntico é sempre um sucesso);
  ///  2. nenhum registro encontrado (`null`) E o código é `P0037` —
  ///     PROMPT 11.5.8.2: diferente de todo o resto, P0037 já É a própria
  ///     RPC confirmando, de forma SÍNCRONA, que um registro DIVERGENTE
  ///     existe para este `loteId` (ver [_codigosRecusaConfirmadosPorAusencia])
  ///     — um `null` NESTA leitura só prova que ELA não conseguiu enxergar
  ///     o registro (RLS/corrida), nunca que ele não existe; como
  ///     `documentos_sei_lotes_conclusao` é append-only (nunca alterada
  ///     depois de inserida), o registro não pode deixar de divergir →
  ///     [SeiConclusaoLoteStatus.conflitoDeIntegridade] com [falhaOriginal];
  ///  3. nenhum registro E o código é um dos
  ///     [_codigosRecusaConfirmadosPorAusencia] (P0010/P0036: a checagem
  ///     que os gera SÓ roda depois do `loteId` já ter sido procurado e não
  ///     encontrado) → a recusa É confiável, nada foi escrito sob este
  ///     `loteId` → [SeiConclusaoLoteStatus.recusado] com [falhaOriginal];
  ///  4. nenhum registro, código fora das duas listas acima (ex.: `42501` —
  ///     checagem de permissão que roda ANTES do lookup do `loteId`) → um
  ///     `null` NÃO prova nada (pode ser a RLS ocultando um registro que
  ///     existe): PERMANECE [SeiConclusaoLoteStatus.resultadoDesconhecido]
  ///     — `loteId` e os seis parâmetros continuam CONGELADOS, `reiniciar`
  ///     continua bloqueado, nenhuma nova decisão é aceita, e a recusa
  ///     NUNCA é apresentada como definitiva;
  ///  5. registro encontrado mas DIVERGENTE ([SeiReconciliacaoDivergenteException])
  ///     → mesmo tratamento de [reconciliar] →
  ///     [SeiConclusaoLoteStatus.conflitoDeIntegridade] (mesmo desfecho de
  ///     2, alcançado pela leitura em vez de inferido só do código).
  /// A própria VERIFICAÇÃO falhando (rede/permissão) nunca vira "recusado"
  /// por padrão: para P0037, permanece o desfecho 2
  /// ([SeiConclusaoLoteStatus.conflitoDeIntegridade] — a certeza já veio da
  /// RPC, independente da leitura funcionar); para qualquer outro código,
  /// volta a [SeiConclusaoLoteStatus.resultadoDesconhecido], igual a
  /// [reconciliar] quando a consulta em si não funciona.
  Future<void> _resolverRecusaDeRetry(SeiDecisaoLoteConfirmada decisao, SeiEscritaFalhouException falhaOriginal) async {
    try {
      final resultado = await ref
          .read(documentosSeiRepositoryProvider)
          .buscarLotePorId(
            loteId: decisao.loteId,
            documentoId: decisao.documentoId,
            itemIds: decisao.itemIds,
            versaoEsperada: decisao.versaoEsperada,
            observacao: decisao.observacao,
            confirmarLimpezaDestino: decisao.confirmarLimpezaDestino,
          );
      if (resultado != null) {
        state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.sucesso, decisao: decisao, resultado: resultado);
        return;
      }
      if (falhaOriginal.codigo == 'P0037') {
        // PROMPT 11.5.8.2 — `null` aqui NUNCA é ausência: P0037 já é a
        // RPC confirmando um registro divergente para este `loteId`.
        state = SeiConclusaoLoteState(
          status: SeiConclusaoLoteStatus.conflitoDeIntegridade,
          decisao: decisao,
          falha: falhaOriginal,
        );
        return;
      }
      if (_codigosRecusaConfirmadosPorAusencia.contains(falhaOriginal.codigo)) {
        state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.recusado, decisao: decisao, falha: falhaOriginal);
        return;
      }
      // PROMPT 11.5.8.1 — `null` aqui NÃO comprova ausência de execução
      // (a RLS pode estar ocultando um registro que existe, se a permissão
      // da sessão mudou entre o retry e esta leitura): a decisão continua
      // CONGELADA e pendente, exatamente como um resultado desconhecido
      // comum — NUNCA apresentada como recusa, nunca libera `reiniciar`,
      // nunca gera um `loteId` novo.
      state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.resultadoDesconhecido, decisao: decisao);
    } on SeiReconciliacaoDivergenteException catch (e) {
      state = SeiConclusaoLoteState(
        status: SeiConclusaoLoteStatus.conflitoDeIntegridade,
        decisao: decisao,
        falha: falhaDeConclusaoSei(
          codigo: 'P0037',
          mensagemDoServidor: e.motivo,
          operacao: operacaoConcluirItensSeiLote,
          cause: e,
        ),
      );
    } catch (_) {
      if (falhaOriginal.codigo == 'P0037') {
        // PROMPT 11.5.8.2 — a própria leitura de verificação falhando não
        // muda nada: a certeza de que há um registro divergente já veio,
        // de forma síncrona, da RPC (o P0037 original) — nunca rebaixada a
        // "resultado desconhecido" só porque não deu para confirmar de novo.
        state = SeiConclusaoLoteState(
          status: SeiConclusaoLoteStatus.conflitoDeIntegridade,
          decisao: decisao,
          falha: falhaOriginal,
        );
        return;
      }
      state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.resultadoDesconhecido, decisao: decisao);
    }
  }

  /// Consulta `documentos_sei_lotes_conclusao` pelo `loteId` CONGELADO
  /// (`DocumentosSeiRepository.buscarLotePorId`) para descobrir se uma
  /// tentativa de resultado desconhecido, na verdade, chegou a ser aplicada
  /// no servidor. Só tem efeito com uma tentativa pendente.
  ///
  /// PROMPT 11.5.6.1 — `buscarLotePorId` já confere a IDENTIDADE COMPLETA
  /// do registro (não só o `loteId`) contra estes mesmos parâmetros; um
  /// `lote_id` batendo sozinho nunca é aceito como prova. Três desfechos
  /// possíveis, tratados de forma DISTINTA (nunca colapsados no mesmo
  /// `catch`):
  ///  1. registro encontrado E idêntico → [SeiConclusaoLoteStatus.sucesso];
  ///  2. nenhum registro (mas a CONSULTA em si funcionou) → continua
  ///     [SeiConclusaoLoteStatus.resultadoDesconhecido] — a ausência
  ///     MOMENTÂNEA não é prova definitiva contra uma corrida (a escrita
  ///     pode não ter commitado ainda no instante exato desta leitura);
  ///  3. registro encontrado mas DIVERGENTE
  ///     ([SeiReconciliacaoDivergenteException]) →
  ///     [SeiConclusaoLoteStatus.conflitoDeIntegridade] (PROMPT 11.5.6.2 —
  ///     NUNCA [SeiConclusaoLoteStatus.recusado]: uma divergência descoberta
  ///     por LEITURA/comparação no cliente não tem a mesma garantia de "a
  ///     transação foi desfeita, nada foi escrito" que uma recusa SÍNCRONA
  ///     do servidor tem — por isso não libera [reiniciar] nem admite
  ///     [retry]/[reconciliar] automáticos; exige investigação fora deste
  ///     controller).
  /// A própria CONSULTA falhando (rede/permissão) — `catch` genérico — NUNCA
  /// é interpretada como "não foi executado": continua pendente, igual ao
  /// caso 2, só que sem sequer ter conseguido perguntar.
  ///
  /// Só tem efeito quando o status é EXATAMENTE
  /// [SeiConclusaoLoteStatus.resultadoDesconhecido] — nunca reconsulta
  /// sozinho um conflito já identificado (ver 3, acima).
  ///
  /// PROMPT 11.5.11 — devolve um [SeiReconciliacaoResultado] descrevendo o
  /// desfecho DESTA chamada (em adição ao `state` emitido, que muda
  /// exatamente como sempre mudou — nenhuma regra/transição abaixo foi
  /// alterada por este retorno): só para a UI conseguir dar feedback
  /// mesmo quando `state.status` permanece [SeiConclusaoLoteStatus.resultadoDesconhecido]
  /// depois da chamada (ver o comentário de [SeiReconciliacaoResultado]).
  Future<SeiReconciliacaoResultado> reconciliar() async {
    final decisao = state.decisao;
    if (state.executando || decisao == null) return SeiReconciliacaoResultado.semEfeito;
    if (state.status != SeiConclusaoLoteStatus.resultadoDesconhecido) return SeiReconciliacaoResultado.semEfeito;
    state = state.copyComExecutando();
    try {
      final resultado = await ref
          .read(documentosSeiRepositoryProvider)
          .buscarLotePorId(
            loteId: decisao.loteId,
            documentoId: decisao.documentoId,
            itemIds: decisao.itemIds,
            versaoEsperada: decisao.versaoEsperada,
            observacao: decisao.observacao,
            confirmarLimpezaDestino: decisao.confirmarLimpezaDestino,
          );
      if (resultado != null) {
        // Registro encontrado E com identidade conferida: a tentativa FOI
        // aplicada (por esta chamada ou por uma tentativa anterior que
        // também tinha dado timeout do lado do cliente, mas chegou ao
        // servidor) — encerra a decisão como sucesso, sem nenhuma nova
        // escrita.
        state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.sucesso, decisao: decisao, resultado: resultado);
        return SeiReconciliacaoResultado.sucesso;
      } else {
        // Nenhum registro: a tentativa pode REALMENTE não ter sido aplicada,
        // ou pode ainda não ter commitado — a ausência não é prova
        // definitiva. Volta a ficar pendente (nunca "resolve" sozinha): o
        // usuário decide entre `retry()` (mesmo payload), consultar de novo
        // depois, ou `reiniciar()` depois de optar por outra abordagem.
        state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.resultadoDesconhecido, decisao: decisao);
        return SeiReconciliacaoResultado.aindaDesconhecido;
      }
    } on SeiReconciliacaoDivergenteException catch (e) {
      // PROMPT 11.5.6.2 — o `lote_id` foi encontrado, mas o registro
      // pertence de fato a uma operação DIFERENTE (parâmetros ou usuário
      // responsável divergem) — erro de integridade, nunca absorvido como
      // sucesso silencioso. NUNCA tratado como `recusado`: essa divergência
      // foi descoberta por uma LEITURA comparada no cliente, não por uma
      // recusa síncrona do servidor — não há a mesma garantia de que "nada
      // foi escrito por ESTA decisão" que uma `SeiEscritaFalhouException`
      // real tem. Fica em `conflitoDeIntegridade`: `decisao` e o motivo
      // técnico (`falha`) permanecem CONGELADOS para diagnóstico, e nem
      // `retry`/`reconciliar` (guardas acima) nem `reiniciar` (guarda em
      // `reiniciar`, via `temTentativaPendente`) fazem algo automaticamente
      // a partir daqui.
      state = SeiConclusaoLoteState(
        status: SeiConclusaoLoteStatus.conflitoDeIntegridade,
        decisao: decisao,
        falha: falhaDeConclusaoSei(
          codigo: 'P0037',
          mensagemDoServidor: e.motivo,
          operacao: operacaoConcluirItensSeiLote,
          cause: e,
        ),
      );
      return SeiReconciliacaoResultado.conflito;
    } catch (_) {
      // A própria consulta de reconciliação falhou (rede/permissão) — NUNCA
      // interpretado como "não foi executado": continua pendente, nada
      // muda.
      state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.resultadoDesconhecido, decisao: decisao);
      return SeiReconciliacaoResultado.falhaDeConsulta;
    }
  }

  /// Encerra a decisão atual — só DEPOIS de [SeiConclusaoLoteStatus.sucesso]
  /// ou [SeiConclusaoLoteStatus.recusado] (uma tentativa pendente nunca deve
  /// ser descartada por engano; o chamador precisa [reconciliar] ou aceitar
  /// explicitamente abandoná-la). Só ENTÃO uma nova [confirmar] é aceita.
  ///
  /// PROMPT 11.5.6.2 — também SEM efeito em
  /// [SeiConclusaoLoteStatus.conflitoDeIntegridade]: um conflito de
  /// integridade não tem, nesta etapa, nenhum caminho automático de saída
  /// por este controller (nem `reiniciar`, nem `retry`, nem `reconciliar`)
  /// — exige investigação fora daqui.
  void reiniciar() {
    // Nunca descarta uma tentativa pendente por engano: enquanto o
    // resultado da chamada anterior for DESCONHECIDO (ou um conflito de
    // integridade não resolvido), só `retry()`/`reconciliar()` — e SÓ a
    // partir de `resultadoDesconhecido`, nunca de um conflito — podem tirar
    // a decisão desse estado. `reiniciar()` sozinho nunca é uma forma de
    // reconciliação.
    if (state.executando || state.temTentativaPendente) return;
    state = const SeiConclusaoLoteState();
  }
}

extension on SeiConclusaoLoteState {
  SeiConclusaoLoteState copyComExecutando() =>
      SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.executando, decisao: decisao);
}

/// PROMPT 11.5.11 — devolvido por [SeiConclusaoLoteController.reconciliar]
/// para o CHAMADOR (a tela) saber o que ACONTECEU nesta tentativa
/// específica de consulta — em ADIÇÃO ao [SeiConclusaoLoteState] emitido
/// (que continua mudando de valor EXATAMENTE como antes: nenhuma
/// regra/transição homologada foi alterada por este enum, só um retorno
/// informativo a mais).
///
/// Causa do bug relatado: [aindaDesconhecido] e [falhaDeConsulta] resultam
/// no MESMO [SeiConclusaoLoteStatus.resultadoDesconhecido] de antes da
/// chamada — o `state` do controller fica byte-a-byte idêntico ao que já
/// era (mesmo `status`, mesma `decisao`, nenhum campo novo), então nada no
/// `switch` do diálogo (`sei_concluir_lote_dialog.dart`) percebia que uma
/// consulta tinha sido feita e "aparentemente nada acontecia" na tela.
/// Este retorno permite ao diálogo mostrar uma mensagem própria SEM
/// duplicar nenhuma regra do controller (nem criar uma segunda máquina de
/// estados: os únicos estados que importam continuam sendo os cinco de
/// [SeiConclusaoLoteStatus] — isto é só metadado do desfecho da ÚLTIMA
/// chamada, descartável a qualquer momento).
enum SeiReconciliacaoResultado {
  /// A chamada não teve efeito: já havia uma chamada em andamento, não
  /// havia decisão pendente, ou o status não era exatamente
  /// [SeiConclusaoLoteStatus.resultadoDesconhecido] (mesmos guards de
  /// sempre) — nenhuma consulta foi feita.
  semEfeito,

  /// Registro encontrado e IDÊNTICO: `state.status` já mudou para
  /// [SeiConclusaoLoteStatus.sucesso].
  sucesso,

  /// A consulta FUNCIONOU, mas nenhum registro foi encontrado (ou a
  /// ausência não pôde ser comprovada) — `state.status` continua
  /// [SeiConclusaoLoteStatus.resultadoDesconhecido], sem nenhuma mudança:
  /// a tentativa original permanece pendente.
  aindaDesconhecido,

  /// A PRÓPRIA consulta falhou (rede/permissão) — `state.status` também
  /// continua [SeiConclusaoLoteStatus.resultadoDesconhecido], mas por um
  /// motivo DIFERENTE de [aindaDesconhecido]: nem sequer foi possível
  /// perguntar ao servidor desta vez.
  falhaDeConsulta,

  /// Registro encontrado mas DIVERGENTE: `state.status` já mudou para
  /// [SeiConclusaoLoteStatus.conflitoDeIntegridade].
  conflito,
}
