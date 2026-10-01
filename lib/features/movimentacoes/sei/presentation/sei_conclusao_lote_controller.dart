import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/uuid_v4.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../application/sei_conclusao_erros.dart';
import '../data/documentos_sei_repository_supabase.dart';
import '../domain/sei_conclusao_lote_resultado.dart';
import '../domain/sei_pendencia_exceptions.dart';

/// Estágio da decisão de conclusão em lote CONGELADA neste controller. Ver
/// [SeiConclusaoLoteState] para o que cada um implica sobre o que pode ser
/// chamado a seguir.
enum SeiConclusaoLoteStatus {
  /// Nenhuma decisão em andamento: [confirmar] pode ser chamado.
  ocioso,

  /// Chamada em voo — qualquer novo clique em
  /// [confirmar]/[retry]/[reconciliar] é ignorado (nunca dispara uma
  /// segunda chamada concorrente).
  executando,

  /// A RPC confirmou (nova conclusão ou retry idêntico) — [resultado]
  /// preenchido. A decisão está ENCERRADA: [reiniciar] é necessário antes
  /// de qualquer nova [confirmar].
  sucesso,

  /// O SERVIDOR recusou explicitamente (`SeiEscritaFalhouException`): a
  /// transação foi desfeita, NADA foi escrito. [reiniciar] é necessário
  /// antes de uma NOVA decisão.
  recusado,

  /// A chamada terminou sem confirmação nem recusa clara do servidor
  /// (timeout, falha de conexão) — o RESULTADO REAL é desconhecido: pode
  /// ter chegado ao servidor e sido aplicado, ou não. A decisão PERMANECE
  /// CONGELADA; só [retry] ou [reconciliar] são permitidos a partir daqui
  /// — nunca [confirmar] com uma seleção nova enquanto este estado
  /// persistir.
  resultadoDesconhecido,

  /// [reconciliar] encontrou, para o `loteId` CONGELADO desta decisão, um
  /// registro em `documentos_sei_lotes_conclusao` cuja identidade DIVERGE
  /// dos parâmetros que esta decisão enviaria. Diferente de [recusado]:
  /// não é uma recusa síncrona do servidor, é uma leitura comparada no
  /// cliente — exige investigação manual. [retry], [reconciliar] e
  /// [reiniciar] ficam todos bloqueados a partir daqui.
  conflitoDeIntegridade,
}

/// Os seis campos da decisão de lote CONGELADOS no momento da confirmação
/// — imutáveis depois de criados. [itemIds] já chega CANÔNICO (distinto,
/// ordenado), para a comparação de identidade de um retry nunca depender
/// da ordem em que o usuário clicou nos itens.
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
  /// `loteId` sozinho.
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

  /// Há uma tentativa NÃO RESOLVIDA — resultado desconhecido ou conflito de
  /// integridade — esperando ação. Enquanto isto for `true`, [confirmar] e
  /// [reiniciar] não têm efeito. Sobrevive a fechar/reabrir um diálogo
  /// enquanto o provider continuar vivo; reiniciar o aplicativo perde essa
  /// informação (sem persistência em disco).
  bool get temTentativaPendente =>
      (status == SeiConclusaoLoteStatus.resultadoDesconhecido || status == SeiConclusaoLoteStatus.conflitoDeIntegridade) &&
      decisao != null;

  /// `true` só no estado de conflito de integridade: nem [retry] nem
  /// [reconciliar] têm efeito a partir daqui — a UI deve mostrar uma
  /// indicação de que o caso exige suporte/investigação, nunca os botões
  /// normais de "tentar novamente".
  bool get emConflitoDeIntegridade => status == SeiConclusaoLoteStatus.conflitoDeIntegridade;

  bool get executando => status == SeiConclusaoLoteStatus.executando;
}

/// Controlador/estado de aplicação da conclusão em lote: congela a decisão
/// confirmada, gera o `loteId` uma única vez, impede chamadas concorrentes
/// e implementa o retry seguro sobre resultado desconhecido (incluindo a
/// reconciliação contra `documentos_sei_lotes_conclusao`). Não constrói
/// nenhuma interface — é puro estado + orquestração de chamadas ao
/// [DocumentosSeiRepository], testável sem `pumpWidget`.
///
/// LIMITAÇÃO: este estado vive só em memória, no processo do app — fechar
/// e reabrir um diálogo preserva a tentativa pendente, mas fechar o
/// aplicativo a perde (sem persistência em disco). Se isso acontecer com
/// uma tentativa de resultado desconhecido em aberto, a única forma de
/// saber o que ocorreu é reler o documento (`obterPorId`) e observar o
/// status dos itens.
///
/// ISOLAMENTO:
///  * ENTRE DOCUMENTOS — provider GLOBAL (não `.family`): enquanto houver
///    uma tentativa pendente para o Documento A, [confirmar] é IGNORADO
///    para qualquer outro documento — o chamador precisa resolver a
///    pendência do Documento A primeiro.
///  * ENTRE SESSÕES — [build] observa [authControllerProvider] só para ser
///    RECRIADO a cada mudança real de sessão (login/logout/troca de
///    usuário): qualquer decisão pendente é DESCARTADA do estado do
///    cliente nesse instante, nunca reaproveitada por outra sessão. Isso
///    não apaga o registro no servidor. Como defesa adicional, a própria
///    RPC e a reconciliação conferem `criado_por`/`auth.uid()` contra a
///    sessão ATUAL — mesmo que o estado local sobrevivesse por algum bug,
///    reenviar/reconciliar sob outro usuário seria recusado.
final seiConclusaoLoteControllerProvider = NotifierProvider<SeiConclusaoLoteController, SeiConclusaoLoteState>(
  SeiConclusaoLoteController.new,
);

class SeiConclusaoLoteController extends Notifier<SeiConclusaoLoteState> {
  /// [gerarLoteId] é injetável só para teste (geração determinística); em
  /// produção, sempre [gerarUuidV4] (UUID v4 aleatório, gerado no cliente —
  /// ver `core/utils/uuid_v4.dart`).
  SeiConclusaoLoteController({String Function()? gerarLoteId}) : _gerarLoteId = gerarLoteId ?? gerarUuidV4;

  final String Function() _gerarLoteId;

  /// Id do usuário (`Profile.id`) da última resolução CONHECIDA de
  /// `authControllerProvider` — usado só para comparar em [build]; a
  /// identidade real do usuário para a escrita/leitura em si é sempre a
  /// sessão ATUAL, resolvida pelo repositório na hora da chamada.
  String? _usuarioConhecido;

  @override
  SeiConclusaoLoteState build() {
    // `ref.watch(authControllerProvider)` faria este `build()` rodar de novo
    // a CADA transição assíncrona do provider de auth (inclusive um refresh
    // trivial do MESMO usuário), apagando uma decisão em andamento à toa.
    // `ref.listen` evita isso: o notifier só reage quando o usuário
    // autenticado RESOLVIDO realmente muda de valor.
    _usuarioConhecido = ref.read(authControllerProvider).value?.profile?.id;
    ref.listen(authControllerProvider, (previous, next) {
      if (!next.hasValue) return; // carregando/erro sem valor — nada a comparar ainda
      final novoUsuario = next.value?.profile?.id;
      if (novoUsuario == _usuarioConhecido) return; // mesmo usuário, ou segue deslogado
      _usuarioConhecido = novoUsuario;
      state = const SeiConclusaoLoteState();
    });
    return const SeiConclusaoLoteState();
  }

  /// Confirma uma NOVA decisão de lote: gera o `loteId` UMA ÚNICA VEZ,
  /// congela os seis parâmetros e dispara a chamada. Ignorado se já houver
  /// uma chamada em andamento ou uma tentativa pendente de reconciliação —
  /// o chamador precisa [retry]/[reconciliar]/[reiniciar] essa tentativa
  /// primeiro; nunca duas decisões concorrentes para o mesmo documento.
  ///
  /// Depois de um [SeiConclusaoLoteStatus.recusado], o chamador deve reler
  /// o documento, atualizar a seleção/dados exibidos e só então chamar
  /// [reiniciar] seguido de um NOVO [confirmar] — nunca reenviar os mesmos
  /// `itemIds`/`versaoEsperada` sem reler.
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
  /// Nenhum retry automático depois de um conflito de integridade: aquele
  /// `loteId` já se mostrou não confiável, reenviá-lo sozinho não é seguro.
  Future<void> retry() async {
    final decisao = state.decisao;
    if (state.executando || decisao == null) return;
    if (state.status != SeiConclusaoLoteStatus.resultadoDesconhecido) return;
    // Um retry nunca aceita uma recusa do servidor como definitiva sem
    // antes conferir `documentos_sei_lotes_conclusao` — diferente da
    // primeira tentativa de [confirmar], que não tem nada anterior com que
    // a recusa possa ser confundida.
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
      // Recusa DEFINITIVA do servidor: qualquer exceção desfaz a transação
      // inteira, sem resíduo — nada foi escrito POR ESTA CHAMADA. Mas isso
      // não prova que a TENTATIVA ORIGINAL (a que gerou o resultado
      // desconhecido, antes deste retry) não foi aplicada: a RPC confere a
      // permissão do usuário ANTES de consultar o `loteId`, então um retry
      // pode ser recusado por permissão mesmo que a tentativa original já
      // tenha sido aplicada sob o MESMO `loteId`. Por isso, só quando
      // [verificarAntesDeRecusar] for `true` (ou seja, um [retry], nunca a
      // primeira tentativa de [confirmar]) a recusa é confirmada por
      // leitura direta antes de ser aceita.
      if (verificarAntesDeRecusar) {
        await _resolverRecusaDeRetry(decisao, falha);
      } else {
        state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.recusado, decisao: decisao, falha: falha);
      }
    } catch (_) {
      // Resultado DESCONHECIDO (rede/timeout/qualquer coisa que não seja
      // uma recusa clara do servidor) — a decisão continua CONGELADA para
      // retry/reconciliar; NUNCA presumida como "falhou no servidor".
      state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.resultadoDesconhecido, decisao: decisao);
    }
  }

  /// Códigos cuja checagem, na RPC real, só roda DEPOIS que o `lote_id` já
  /// foi consultado e NADA foi encontrado. Só para ESTES códigos um
  /// `buscarLotePorId` que devolve `null` é aceito como PROVA de que nada
  /// foi escrito sob este `loteId` — qualquer outro código nunca tem essa
  /// garantia (ex.: `42501`, checagem de permissão que roda ANTES do
  /// lookup do `loteId`: um `null` pode significar "não existe" ou "existe,
  /// mas a sessão atual não enxerga por RLS").
  ///
  /// `P0037` NÃO entra nesta lista: diferente de P0010/P0036, só é lançado
  /// quando o lote FOI ENCONTRADO e diverge — nunca por ausência. Um retry
  /// recebendo P0037 já é, por si só, a RPC confirmando de forma síncrona
  /// que existe um registro divergente (tratado à parte em
  /// [_resolverRecusaDeRetry]).
  static const _codigosRecusaConfirmadosPorAusencia = {'P0010', 'P0036'};

  /// Só chamado a partir de um [retry] que recebeu uma
  /// [SeiEscritaFalhouException]. Confere `documentos_sei_lotes_conclusao`
  /// pelo `loteId` CONGELADO antes de aceitar a recusa como definitiva.
  /// Desfechos, nunca colapsados:
  ///  1. registro encontrado e idêntico → a tentativa FOI aplicada →
  ///     [SeiConclusaoLoteStatus.sucesso] (vale para qualquer código, P0037
  ///     incluído: um match idêntico é sempre um sucesso);
  ///  2. nenhum registro e o código é `P0037` → um `null` aqui só prova que
  ///     esta leitura não conseguiu enxergar o registro, nunca que ele não
  ///     existe (a tabela é append-only) →
  ///     [SeiConclusaoLoteStatus.conflitoDeIntegridade];
  ///  3. nenhum registro e o código é um dos
  ///     [_codigosRecusaConfirmadosPorAusencia] → a recusa é confiável →
  ///     [SeiConclusaoLoteStatus.recusado];
  ///  4. nenhum registro, código fora das duas listas (ex.: `42501`) → um
  ///     `null` não prova nada → PERMANECE
  ///     [SeiConclusaoLoteStatus.resultadoDesconhecido];
  ///  5. registro encontrado mas DIVERGENTE → mesmo tratamento de
  ///     [reconciliar] → [SeiConclusaoLoteStatus.conflitoDeIntegridade].
  /// A própria VERIFICAÇÃO falhando (rede/permissão) nunca vira "recusado":
  /// para P0037 permanece o desfecho 2; para qualquer outro código volta a
  /// [SeiConclusaoLoteStatus.resultadoDesconhecido].
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
        // `null` aqui NUNCA é ausência: P0037 já é a RPC confirmando um
        // registro divergente para este `loteId`.
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
      // `null` aqui não comprova ausência de execução (a RLS pode estar
      // ocultando um registro que existe) — a decisão continua CONGELADA e
      // pendente, nunca apresentada como recusa.
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
        // A própria leitura de verificação falhando não muda nada: a
        // certeza de um registro divergente já veio, de forma síncrona, da
        // RPC — nunca rebaixada a "resultado desconhecido".
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
  /// para descobrir se uma tentativa de resultado desconhecido, na
  /// verdade, chegou a ser aplicada no servidor. Só tem efeito com uma
  /// tentativa pendente e status EXATAMENTE
  /// [SeiConclusaoLoteStatus.resultadoDesconhecido].
  ///
  /// `buscarLotePorId` confere a IDENTIDADE COMPLETA do registro (não só o
  /// `loteId`); um `lote_id` batendo sozinho nunca é aceito como prova.
  /// Três desfechos, tratados de forma distinta:
  ///  1. registro encontrado e idêntico → [SeiConclusaoLoteStatus.sucesso];
  ///  2. nenhum registro (consulta funcionou) → continua
  ///     [SeiConclusaoLoteStatus.resultadoDesconhecido] — a ausência
  ///     momentânea não é prova definitiva contra uma corrida;
  ///  3. registro encontrado mas DIVERGENTE →
  ///     [SeiConclusaoLoteStatus.conflitoDeIntegridade] (NUNCA
  ///     [SeiConclusaoLoteStatus.recusado]: uma divergência descoberta por
  ///     leitura no cliente não tem a mesma garantia que uma recusa
  ///     síncrona do servidor).
  /// A própria consulta falhando (rede/permissão) nunca é interpretada como
  /// "não foi executado": continua pendente, igual ao caso 2.
  ///
  /// Devolve um [SeiReconciliacaoResultado] descrevendo o desfecho desta
  /// chamada, em adição ao `state` emitido — só para a UI dar feedback
  /// mesmo quando `state.status` não muda de valor.
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
        // Registro encontrado e com identidade conferida: a tentativa FOI
        // aplicada — encerra a decisão como sucesso, sem nenhuma nova
        // escrita.
        state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.sucesso, decisao: decisao, resultado: resultado);
        return SeiReconciliacaoResultado.sucesso;
      } else {
        // Nenhum registro: a tentativa pode REALMENTE não ter sido
        // aplicada, ou pode ainda não ter commitado — a ausência não é
        // prova definitiva. Volta a ficar pendente (nunca "resolve"
        // sozinha).
        state = SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.resultadoDesconhecido, decisao: decisao);
        return SeiReconciliacaoResultado.aindaDesconhecido;
      }
    } on SeiReconciliacaoDivergenteException catch (e) {
      // O `lote_id` foi encontrado, mas o registro pertence de fato a uma
      // operação DIFERENTE — erro de integridade, nunca absorvido como
      // sucesso silencioso. NUNCA tratado como `recusado`: essa divergência
      // foi descoberta por uma leitura comparada no cliente, não por uma
      // recusa síncrona do servidor.
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
  /// ser descartada por engano; o chamador precisa [reconciliar] primeiro).
  /// Também SEM efeito em [SeiConclusaoLoteStatus.conflitoDeIntegridade]:
  /// não tem, nesta etapa, nenhum caminho automático de saída — exige
  /// investigação fora daqui.
  void reiniciar() {
    if (state.executando || state.temTentativaPendente) return;
    state = const SeiConclusaoLoteState();
  }
}

extension on SeiConclusaoLoteState {
  SeiConclusaoLoteState copyComExecutando() =>
      SeiConclusaoLoteState(status: SeiConclusaoLoteStatus.executando, decisao: decisao);
}

/// Devolvido por [SeiConclusaoLoteController.reconciliar] para o chamador
/// (a tela) saber o que ACONTECEU nesta tentativa específica de consulta —
/// em adição ao [SeiConclusaoLoteState] emitido. [aindaDesconhecido] e
/// [falhaDeConsulta] resultam no mesmo
/// [SeiConclusaoLoteStatus.resultadoDesconhecido] de antes da chamada (o
/// `state` fica idêntico), então este retorno existe para a UI conseguir
/// dar um feedback próprio mesmo quando nada no `state` mudou.
enum SeiReconciliacaoResultado {
  /// A chamada não teve efeito: já havia uma chamada em andamento, não
  /// havia decisão pendente, ou o status não era exatamente
  /// [SeiConclusaoLoteStatus.resultadoDesconhecido] — nenhuma consulta foi
  /// feita.
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
