import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/utils/uuid_v4.dart';
import '../../../auth/domain/profile.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/patrimonio_repository_supabase.dart';
import '../../domain/patrimonio_repository.dart';
import '../domain/comparacao_execucao.dart';
import '../domain/patrimonio_comparacao.dart';
import '../domain/patrimonio_decisao.dart';

/// Máximo de chamadas simultâneas a `aplicar_decisao_comparacao_patrimonio`
/// — evita uma operação monolítica, usando lotes transacionais de tamanho
/// controlado; mesmo valor e mesmo padrão de
/// `importConcorrenciaMaxima`/`_executarLote` já usados pela importação
/// convencional.
const comparacaoExecucaoConcorrenciaMaxima = 5;

/// Desfecho de UM patrimônio dentro de uma execução em andamento/concluída.
enum ItemExecucaoStatus {
  /// Ainda não processado (esperando sua vez no lote).
  pendente,

  /// Chamada em voo.
  executando,

  /// A RPC confirmou (nova escrita OU retry idêntico já registrado — ver
  /// [ResultadoAplicacaoDecisao.jaExecutado]).
  sucesso,

  /// O SERVIDOR recusou de forma síncrona
  /// ([ComparacaoExecucaoFalhouException]) — a transação foi desfeita, nada
  /// foi escrito para ESTE patrimônio. Encerrado: exige uma NOVA
  /// comparação/revisão deste patrimônio, nunca um retry automático (o
  /// motivo — conflito de versão, pendência SEI, validação — não desaparece
  /// reenviando os mesmos parâmetros).
  falha,

  /// A chamada terminou sem confirmação nem recusa clara do servidor
  /// (rede/timeout) — o resultado real é DESCONHECIDO: só [
  /// ComparacaoExecucaoController.retryItem] (reenvia o MESMO payload,
  /// seguro por idempotência) ou [ComparacaoExecucaoController.reconciliarItem]
  /// (consulta somente-leitura) são permitidos a partir daqui.
  resultadoDesconhecido,
}

/// Estado de UM patrimônio dentro da execução — [decisao] é a mesma
/// instância CONGELADA desde [ComparacaoExecucaoController.confirmar] (nunca
/// recriada, nem no retry).
class ItemExecucaoEstado {
  const ItemExecucaoEstado({
    required this.decisao,
    this.status = ItemExecucaoStatus.pendente,
    this.resultado,
    this.falha,
  });

  final DecisaoItemParaExecutar decisao;
  final ItemExecucaoStatus status;
  final ResultadoAplicacaoDecisao? resultado;
  final ComparacaoExecucaoFalhouException? falha;

  ItemExecucaoEstado copiarCom({
    ItemExecucaoStatus? status,
    ResultadoAplicacaoDecisao? resultado,
    ComparacaoExecucaoFalhouException? falha,
  }) {
    return ItemExecucaoEstado(
      decisao: decisao,
      status: status ?? this.status,
      resultado: resultado ?? this.resultado,
      falha: falha ?? this.falha,
    );
  }
}

enum ComparacaoExecucaoFase { ociosa, executando, concluida }

class ComparacaoExecucaoState {
  const ComparacaoExecucaoState({
    this.fase = ComparacaoExecucaoFase.ociosa,
    this.itens = const {},
    this.loteId,
    this.justificativa,
  });

  final ComparacaoExecucaoFase fase;

  /// Chave: `patrimonioId` — nunca um índice de lista (mesmo cuidado de
  /// [ChaveDecisaoCampo]).
  final Map<String, ItemExecucaoEstado> itens;
  final String? loteId;
  final String? justificativa;

  bool get executando => fase == ComparacaoExecucaoFase.executando;

  /// existe ao menos um item cujo resultado real
  /// é DESCONHECIDO: enquanto isto for `true`, nenhuma nova comparação nem
  /// nova execução pode começar (o chamador precisa resolver via
  /// [ComparacaoExecucaoController.retryItem]/[ComparacaoExecucaoController.reconciliarItem]
  /// primeiro).
  bool get temPendencia => itens.values.any((item) => item.status == ItemExecucaoStatus.resultadoDesconhecido);

  bool get podeIniciarNovaExecucao => !executando && !temPendencia;

  int get total => itens.length;
  int get sucessos => _contar(ItemExecucaoStatus.sucesso);
  int get falhas => _contar(ItemExecucaoStatus.falha);
  int get desconhecidos => _contar(ItemExecucaoStatus.resultadoDesconhecido);
  int get processados => sucessos + falhas + desconhecidos;

  int _contar(ItemExecucaoStatus status) => itens.values.where((item) => item.status == status).length;
}

final comparacaoExecucaoControllerProvider = NotifierProvider<ComparacaoExecucaoController, ComparacaoExecucaoState>(
  ComparacaoExecucaoController.new,
);

/// orquestra a execução SEGURA das decisões preparadas em
/// `PatrimonioImportState.decisoes`: congela a lista de itens na
/// confirmação, chama [PatrimonioRepository.aplicarDecisaoComparacao] UMA
/// VEZ POR PATRIMÔNIO com concorrência limitada, e nunca esconde um
/// resultado desconhecido como se fosse sucesso ou falha.
///
/// Deliberadamente um provider SEPARADO de [PatrimonioImportController]
/// (mesma decisão de design de `SeiConclusaoLoteController` em relação aos
/// controllers de edição SEI): mantém a máquina de estados de execução
/// isolada da máquina de estados de comparação/decisão, que continua
/// funcionando exatamente como antes.
class ComparacaoExecucaoController extends Notifier<ComparacaoExecucaoState> {
  /// [comparacaoExecucaoHabilitada] é injetável só para teste (padrão:
  /// sempre [EnvConfig.comparacaoExecucaoHabilitada], NUNCA `true` fixo em
  /// produção) — mesmo padrão de [gerarLoteId] injetável em
  /// `SeiConclusaoLoteController`.
  ComparacaoExecucaoController({
    String Function()? gerarLoteId,
    String Function()? gerarOperacaoId,
    bool Function()? comparacaoExecucaoHabilitada,
  }) : _gerarLoteId = gerarLoteId ?? gerarUuidV4,
       _gerarOperacaoId = gerarOperacaoId ?? gerarUuidV4,
       _comparacaoExecucaoHabilitada = comparacaoExecucaoHabilitada ?? (() => EnvConfig.comparacaoExecucaoHabilitada);

  final String Function() _gerarLoteId;
  final String Function() _gerarOperacaoId;
  final bool Function() _comparacaoExecucaoHabilitada;

  /// Mesmo papel de `_usuarioConhecido` em `SeiConclusaoLoteController`/
  /// `PatrimonioImportController`: só para [build] comparar e nunca lido
  /// diretamente pela escrita em si.
  String? _usuarioConhecido;

  @override
  ComparacaoExecucaoState build() {
    _usuarioConhecido = ref.read(authControllerProvider).value?.profile?.id;
    ref.listen(authControllerProvider, (previous, next) {
      if (!next.hasValue) return;
      final novo = next.value?.profile?.id;
      if (novo == _usuarioConhecido) return;
      _usuarioConhecido = novo;
      // Troca de usuário: descarta o estado local (nunca reaproveitado por
      // uma sessão diferente da que confirmou); o servidor já registrou o
      // que realmente foi aplicado, então nada se perde de verdade, só a
      // "memória" desta tela.
      state = const ComparacaoExecucaoState();
    });
    return const ComparacaoExecucaoState();
  }

  /// Confirma e dispara a execução de uma NOVA rodada de decisões. Sem
  /// efeito se já houver uma execução em andamento ou uma pendência não
  /// resolvida ([ComparacaoExecucaoState.podeIniciarNovaExecucao]), ou se
  /// [construirItensParaExecucao] não encontrar nenhum item elegível (nada
  /// selecionado para aplicar).
  Future<void> confirmar({
    required ComparacaoLote comparacao,
    required Map<ChaveDecisaoCampo, DecisaoCampoValor> decisoes,
    required String justificativa,
  }) async {
    // validação obrigatória em TRÊS camadas: esta é
    // a camada do controller (a UI já esconde o botão para não-ADMIN, e a
    // RPC exige ADMIN no servidor — nenhuma delas sozinha é suficiente).
    // Nunca confiar que só esconder o botão já impede a chamada.
    if (ref.read(authControllerProvider).value?.profile?.perfil != ProfilePerfil.admin) return;

    // trava operacional adicional, independente do
    // perfil ADMIN e de `kReleaseMode`: enquanto
    // `EnvConfig.comparacaoExecucaoHabilitada` for `false` (padrão), nenhuma
    // execução real é disparada, mesmo que a migration já exista no banco e
    // mesmo que a sessão seja ADMIN. A comparação/revisão de divergências
    // (`PatrimonioImportController.compararParaAdmin`) NUNCA passa por
    // aqui — continua disponível normalmente.
    if (!_comparacaoExecucaoHabilitada()) return;

    if (!state.podeIniciarNovaExecucao) return;

    final loteId = _gerarLoteId();
    final itens = construirItensParaExecucao(
      comparacao: comparacao,
      decisoes: decisoes,
      loteId: loteId,
      justificativa: justificativa,
      gerarOperacaoId: _gerarOperacaoId,
    );
    if (itens.isEmpty) return;

    state = ComparacaoExecucaoState(
      fase: ComparacaoExecucaoFase.executando,
      itens: {for (final item in itens) item.patrimonioId: ItemExecucaoEstado(decisao: item)},
      loteId: loteId,
      justificativa: justificativa,
    );

    await _processar(itens);
  }

  Future<void> _processar(List<DecisaoItemParaExecutar> itens) async {
    final repositorio = ref.read(patrimonioRepositoryProvider);
    final usuarioNoInicio = _usuarioConhecido;
    for (var i = 0; i < itens.length; i += comparacaoExecucaoConcorrenciaMaxima) {
      // Uma troca de usuário interrompe novas solicitações: nunca dispara
      // mais chamadas depois que a sessão que confirmou mudou (chamadas já
      // em voo terminam normalmente; ver o comentário de [build] sobre por
      // que uma atualização perdida delas é segura).
      if (ref.read(authControllerProvider).value?.profile?.id != usuarioNoInicio) break;
      final fim = (i + comparacaoExecucaoConcorrenciaMaxima).clamp(0, itens.length);
      final lote = itens.sublist(i, fim);
      await Future.wait(lote.map((item) => _executarItem(repositorio, item)));
    }
    if (state.fase == ComparacaoExecucaoFase.executando) {
      state = ComparacaoExecucaoState(
        fase: ComparacaoExecucaoFase.concluida,
        itens: state.itens,
        loteId: state.loteId,
        justificativa: state.justificativa,
      );
    }
  }

  Future<void> _executarItem(PatrimonioRepository repositorio, DecisaoItemParaExecutar item) async {
    _atualizarItem(item.patrimonioId, (e) => e.copiarCom(status: ItemExecucaoStatus.executando));
    try {
      final resultado = await repositorio.aplicarDecisaoComparacao(item);
      _atualizarItem(
        item.patrimonioId,
        (e) => e.copiarCom(status: ItemExecucaoStatus.sucesso, resultado: resultado),
      );
    } on ComparacaoExecucaoFalhouException catch (falha) {
      _atualizarItem(item.patrimonioId, (e) => e.copiarCom(status: ItemExecucaoStatus.falha, falha: falha));
    } catch (_) {
      // Resultado DESCONHECIDO (rede/timeout/qualquer coisa que não seja
      // uma recusa clara do servidor) — nunca presumido como "falhou".
      _atualizarItem(item.patrimonioId, (e) => e.copiarCom(status: ItemExecucaoStatus.resultadoDesconhecido));
    }
  }

  void _atualizarItem(String patrimonioId, ItemExecucaoEstado Function(ItemExecucaoEstado) atualizar) {
    final atual = state.itens[patrimonioId];
    // `null` acontece quando o estado já foi resetado (troca de usuário/
    // `reiniciar`) enquanto esta chamada específica ainda estava em voo —
    // nunca ressuscita um item de uma rodada/sessão já descartada.
    if (atual == null) return;
    final novoMapa = Map<String, ItemExecucaoEstado>.from(state.itens)..[patrimonioId] = atualizar(atual);
    state = ComparacaoExecucaoState(
      fase: state.fase,
      itens: novoMapa,
      loteId: state.loteId,
      justificativa: state.justificativa,
    );
  }

  /// Reenvia a MESMA decisão congelada de um item em
  /// [ItemExecucaoStatus.resultadoDesconhecido] — nunca gera um novo
  /// `operacaoId` (a idempotência do lado do servidor faz o resto: se a
  /// tentativa original já havia escrito, a RPC devolve o resultado já
  /// gravado sem nenhuma nova escrita). Sem efeito se já estiver executando
  /// ou se o item não estiver exatamente nesse estado.
  Future<void> retryItem(String patrimonioId) async {
    if (state.executando) return;
    final atual = state.itens[patrimonioId];
    if (atual == null || atual.status != ItemExecucaoStatus.resultadoDesconhecido) return;

    state = ComparacaoExecucaoState(
      fase: ComparacaoExecucaoFase.executando,
      itens: state.itens,
      loteId: state.loteId,
      justificativa: state.justificativa,
    );
    await _executarItem(ref.read(patrimonioRepositoryProvider), atual.decisao);
    if (state.fase == ComparacaoExecucaoFase.executando) {
      state = ComparacaoExecucaoState(
        fase: ComparacaoExecucaoFase.concluida,
        itens: state.itens,
        loteId: state.loteId,
        justificativa: state.justificativa,
      );
    }
  }

  /// Consulta somente-leitura de `patrimonio_comparacao_execucoes` (nunca
  /// uma nova escrita) — para descobrir se um item de resultado desconhecido
  /// já tinha, na verdade, sido aplicado por uma tentativa anterior. `null`
  /// devolvido pela consulta NUNCA é tratado como "não aconteceu" (a
  /// ausência momentânea não é prova contra uma corrida) — o item continua
  /// [ItemExecucaoStatus.resultadoDesconhecido].
  Future<void> reconciliarItem(String patrimonioId) async {
    if (state.executando) return;
    final atual = state.itens[patrimonioId];
    if (atual == null || atual.status != ItemExecucaoStatus.resultadoDesconhecido) return;
    try {
      final resultado = await ref
          .read(patrimonioRepositoryProvider)
          .buscarExecucaoComparacaoPorOperacaoId(atual.decisao.operacaoId);
      if (resultado != null) {
        _atualizarItem(
          patrimonioId,
          (e) => e.copiarCom(status: ItemExecucaoStatus.sucesso, resultado: resultado),
        );
      }
    } catch (_) {
      // A própria consulta falhou (rede/permissão) — nunca interpretado
      // como "não foi executado": o item continua pendente, nada muda.
    }
  }

  /// Limpa o estado — só fora de uma execução e sem nenhuma pendência
  /// (mesma guarda de `SeiConclusaoLoteController.reiniciar`): uma
  /// tentativa de resultado desconhecido nunca é descartada por engano.
  void reiniciar() {
    if (state.executando || state.temPendencia) return;
    state = const ComparacaoExecucaoState();
  }
}
