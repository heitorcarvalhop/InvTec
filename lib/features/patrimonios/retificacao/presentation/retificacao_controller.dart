import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/utils/uuid_v4.dart';
import '../../../auth/domain/profile.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/current_permissions_controller.dart';
import '../../../setores/data/setor_repository_supabase.dart';
import '../../data/patrimonio_repository_supabase.dart';
import '../../domain/patrimonio_detalhe.dart';
import '../../domain/patrimonio_repository.dart';
import '../domain/retificacao_comparacao.dart';
import '../domain/retificacao_csv_parser.dart';
import '../domain/retificacao_execucao.dart';

/// Máximo de chamadas simultâneas ao resolver os patrimônios do CSV por
/// UUID (nunca uma por vez, nunca todas de uma vez) — mesmo papel de
/// [retificacaoExecucaoConcorrenciaMaxima], só que para LEITURA.
const retificacaoResolucaoConcorrenciaMaxima = 5;

/// A EXECUÇÃO real (ao contrário da resolução de leitura acima) é
/// SEQUENCIAL — um item por vez, nunca em lote concorrente. Decisão
/// explícita para a campanha dos 104 (diferente de
/// `ComparacaoExecucaoController`, que usa lotes de 5): acompanhamento
/// individual e a possibilidade de interromper com segurança ANTES do
/// próximo item (ver [RetificacaoController.solicitarInterrupcao]) só fazem
/// sentido um item por vez.

enum RetificacaoFase {
  /// Nenhum CSV carregado ainda.
  semArquivo,

  /// Lendo o CSV e resolvendo cada patrimônio por UUID contra o InvTec.
  carregando,

  /// Comparação pronta — tela de prévia, aguardando justificativa e
  /// confirmação explícita.
  revisao,

  /// Execução em andamento (gatilhada por [RetificacaoController.
  /// confirmarExecucao]).
  executando,

  concluida,
}

enum ItemExecucaoRetificacaoStatus {
  pendente,
  executando,

  /// A RPC confirmou (nova escrita OU retry idêntico já registrado — ver
  /// [ResultadoRetificacaoUnidade.jaExecutado]).
  sucesso,

  /// O SERVIDOR recusou de forma síncrona — nada foi escrito para ESTE
  /// patrimônio. Encerrado: exige revisão manual, nunca um retry
  /// automático (o motivo não desaparece reenviando os mesmos parâmetros).
  falha,

  /// A chamada terminou sem confirmação nem recusa clara do servidor
  /// (rede/timeout) — resultado REAL desconhecido. Só [RetificacaoController
  /// .retryItem] (reenvia o MESMO payload, seguro por idempotência) é
  /// permitido a partir daqui.
  resultadoDesconhecido,
}

class ItemExecucaoRetificacaoEstado {
  const ItemExecucaoRetificacaoEstado({
    required this.item,
    this.status = ItemExecucaoRetificacaoStatus.pendente,
    this.resultado,
    this.falha,
  });

  final ItemRetificacaoParaExecutar item;
  final ItemExecucaoRetificacaoStatus status;
  final ResultadoRetificacaoUnidade? resultado;
  final RetificacaoExecucaoFalhouException? falha;

  ItemExecucaoRetificacaoEstado copiarCom({
    ItemExecucaoRetificacaoStatus? status,
    ResultadoRetificacaoUnidade? resultado,
    RetificacaoExecucaoFalhouException? falha,
  }) {
    return ItemExecucaoRetificacaoEstado(
      item: item,
      status: status ?? this.status,
      resultado: resultado ?? this.resultado,
      falha: falha ?? this.falha,
    );
  }
}

class RetificacaoState {
  const RetificacaoState({
    this.fase = RetificacaoFase.semArquivo,
    this.lote,
    this.loteId,
    this.justificativa = '',
    this.erroCarregamento,
    this.itensExecucao = const {},
    this.interrompidaPeloUsuario = false,
  });

  final RetificacaoFase fase;
  final RetificacaoLote? lote;
  final String? loteId;
  final String justificativa;

  /// Preenchido só quando o carregamento/parse do CSV falhou — nunca
  /// confundido com uma linha bloqueada (que faz parte normal de [lote]).
  final Object? erroCarregamento;

  /// Chave: `patrimonioId` — nunca um índice de lista.
  final Map<String, ItemExecucaoRetificacaoEstado> itensExecucao;

  /// `true` quando a rodada concluída foi parada por
  /// [RetificacaoController.solicitarInterrupcao] (nunca por falha) — nunca
  /// confundido com "todos os itens já foram processados". Só tem sentido
  /// em [RetificacaoFase.concluida]; sempre `false` nas demais fases.
  final bool interrompidaPeloUsuario;

  bool get executando => fase == RetificacaoFase.executando;

  bool get temPendencia =>
      itensExecucao.values.any((item) => item.status == ItemExecucaoRetificacaoStatus.resultadoDesconhecido);

  bool get podeIniciarNovaExecucao => !executando && !temPendencia;

  int get totalExecucao => itensExecucao.length;
  int get sucessos => _contar(ItemExecucaoRetificacaoStatus.sucesso);
  int get falhas => _contar(ItemExecucaoRetificacaoStatus.falha);
  int get desconhecidos => _contar(ItemExecucaoRetificacaoStatus.resultadoDesconhecido);
  int get processados => sucessos + falhas + desconhecidos;

  int _contar(ItemExecucaoRetificacaoStatus status) =>
      itensExecucao.values.where((item) => item.status == status).length;
}

final retificacaoControllerProvider = NotifierProvider<RetificacaoController, RetificacaoState>(
  RetificacaoController.new,
);

/// Orquestra o fluxo completo de retificação cadastral de unidade: carrega
/// e resolve o CSV local (nunca por texto — sempre por UUID), expõe a
/// prévia/comparação para revisão humana, e só então, com confirmação
/// explícita, executa cada item com concorrência limitada — nunca uma
/// operação monolítica, nunca escondendo um resultado desconhecido como se
/// fosse sucesso ou falha.
///
/// Trava adicional, independente da permissão `patrimonio.rectify_unit`:
/// [EnvConfig.retificacaoExecucaoHabilitada] (padrão `false`) precisa estar
/// explicitamente habilitada para [confirmarExecucao] fazer qualquer
/// chamada real — mesmo que a migration já exista no banco e mesmo que a
/// sessão seja ADMIN/GESTOR. A prévia/comparação nunca passa por essa
/// trava (é sempre só leitura).
class RetificacaoController extends Notifier<RetificacaoState> {
  RetificacaoController({
    String Function()? gerarLoteId,
    String Function()? gerarOperacaoId,
    bool Function()? retificacaoExecucaoHabilitada,
  }) : _gerarLoteId = gerarLoteId ?? gerarUuidV4,
       _gerarOperacaoId = gerarOperacaoId ?? gerarUuidV4,
       _retificacaoExecucaoHabilitada = retificacaoExecucaoHabilitada ?? (() => EnvConfig.retificacaoExecucaoHabilitada);

  final String Function() _gerarLoteId;
  final String Function() _gerarOperacaoId;
  final bool Function() _retificacaoExecucaoHabilitada;

  /// Mesmo papel de `_usuarioConhecido` em `ComparacaoExecucaoController`.
  String? _usuarioConhecido;

  /// Pedido de parada ANTES do próximo item — nunca cancela uma chamada já
  /// em voo (ver [solicitarInterrupcao]).
  bool _interrupcaoSolicitada = false;

  @override
  RetificacaoState build() {
    _usuarioConhecido = ref.read(authControllerProvider).value?.profile?.id;
    ref.listen(authControllerProvider, (previous, next) {
      if (!next.hasValue) return;
      final novo = next.value?.profile?.id;
      if (novo == _usuarioConhecido) return;
      _usuarioConhecido = novo;
      state = const RetificacaoState();
    });
    return const RetificacaoState();
  }

  /// Decodifica, interpreta e resolve [bytesCsv] (nunca presume UTF-8: cai
  /// para Latin-1 se a decodificação estrita falhar — exportações locais
  /// de planilha às vezes saem em Windows-1252/Latin-1). Sem efeito
  /// enquanto já houver uma execução em andamento.
  Future<void> carregarCsv(List<int> bytesCsv) async {
    if (state.executando) return;

    state = RetificacaoState(fase: RetificacaoFase.carregando, justificativa: state.justificativa);

    try {
      String texto;
      try {
        texto = utf8.decode(bytesCsv);
      } on FormatException {
        texto = latin1.decode(bytesCsv);
      }

      final linhas = RetificacaoCsvParser.parse(texto);
      final repositorio = ref.read(patrimonioRepositoryProvider);

      // Resolução por UUID (nunca por número/texto) — em lotes de
      // concorrência limitada, nunca uma consulta por vez nem todas de
      // uma vez. IDs duplicados no CSV (não deveria ocorrer, mas nunca
      // confiado) resolvidos uma única vez.
      final idsUnicos = linhas.map((l) => l.patrimonioId).toSet().toList();
      final patrimoniosPorId = <String, PatrimonioDetalhe>{};
      for (var i = 0; i < idsUnicos.length; i += retificacaoResolucaoConcorrenciaMaxima) {
        final fim = (i + retificacaoResolucaoConcorrenciaMaxima).clamp(0, idsUnicos.length);
        final idsDoLote = idsUnicos.sublist(i, fim);
        final resultados = await Future.wait(idsDoLote.map(repositorio.buscarDetalhePorId));
        for (var j = 0; j < idsDoLote.length; j++) {
          final detalhe = resultados[j];
          if (detalhe != null) patrimoniosPorId[idsDoLote[j]] = detalhe;
        }
      }

      final setores = await ref.read(setorRepositoryProvider).listarAtivos();

      final lote = RetificacaoComparador.comparar(
        linhas: linhas,
        patrimoniosPorId: patrimoniosPorId,
        setores: setores,
      );

      state = RetificacaoState(fase: RetificacaoFase.revisao, lote: lote, justificativa: state.justificativa);
    } catch (e) {
      state = RetificacaoState(fase: RetificacaoFase.semArquivo, erroCarregamento: e);
    }
  }

  void definirJustificativa(String valor) {
    if (state.executando) return;
    state = RetificacaoState(
      fase: state.fase,
      lote: state.lote,
      loteId: state.loteId,
      justificativa: valor,
      itensExecucao: state.itensExecucao,
      interrompidaPeloUsuario: state.interrompidaPeloUsuario,
    );
  }

  /// Confirma e dispara a execução de uma NOVA rodada — validação em TRÊS
  /// camadas, nenhuma delas sozinha suficiente (mesmo padrão de
  /// `ComparacaoExecucaoController.confirmar`): (1) perfil ADMIN ou GESTOR,
  /// (2) permissão granular `patrimonio.rectify_unit` (pode ter sido
  /// revogada por override mesmo de um ADMIN/GESTOR), (3)
  /// [EnvConfig.retificacaoExecucaoHabilitada] — trava operacional
  /// independente das duas primeiras. A RPC no servidor é a autoridade
  /// real; estas três camadas são defesa em profundidade, nunca um
  /// substituto dela.
  Future<void> confirmarExecucao() async {
    final lote = state.lote;
    if (lote == null) return;
    if (!state.podeIniciarNovaExecucao) return;

    final perfil = ref.read(authControllerProvider).value?.profile?.perfil;
    if (perfil != ProfilePerfil.admin && perfil != ProfilePerfil.gestor) return;

    final permissoes = await ref.read(currentPermissionsControllerProvider.future);
    if (!permissoes.hasPermission('patrimonio.rectify_unit')) return;

    if (!_retificacaoExecucaoHabilitada()) return;

    final justificativa = state.justificativa.trim();
    if (justificativa.isEmpty) return;

    final loteId = _gerarLoteId();
    final itens = construirItensRetificacaoParaExecucao(
      lote: lote,
      loteId: loteId,
      justificativa: justificativa,
      gerarOperacaoId: _gerarOperacaoId,
    );
    if (itens.isEmpty) return;

    _interrupcaoSolicitada = false;
    state = RetificacaoState(
      fase: RetificacaoFase.executando,
      lote: lote,
      loteId: loteId,
      justificativa: state.justificativa,
      itensExecucao: {for (final item in itens) item.patrimonioId: ItemExecucaoRetificacaoEstado(item: item)},
    );

    await _processar(itens);
  }

  /// Sequencial — um item por vez (ver comentário de
  /// `retificacaoResolucaoConcorrenciaMaxima`): cada chamada só começa
  /// depois que a anterior já terminou, seja sucesso, falha ou resultado
  /// desconhecido.
  Future<void> _processar(List<ItemRetificacaoParaExecutar> itens) async {
    final repositorio = ref.read(patrimonioRepositoryProvider);
    final usuarioNoInicio = _usuarioConhecido;
    var interrompida = false;
    for (final item in itens) {
      // Troca de usuário interrompe novas solicitações — chamadas já em
      // voo terminam normalmente (mesma garantia de
      // ComparacaoExecucaoController._processar).
      if (ref.read(authControllerProvider).value?.profile?.id != usuarioNoInicio) break;
      // Pedido explícito de interrupção — checado ANTES de cada item, nunca
      // no meio de uma chamada já em voo (ver solicitarInterrupcao).
      if (_interrupcaoSolicitada) {
        interrompida = true;
        break;
      }
      await _executarItem(repositorio, item);
    }
    _interrupcaoSolicitada = false;
    if (state.fase == RetificacaoFase.executando) {
      state = RetificacaoState(
        fase: RetificacaoFase.concluida,
        lote: state.lote,
        loteId: state.loteId,
        justificativa: state.justificativa,
        itensExecucao: state.itensExecucao,
        interrompidaPeloUsuario: interrompida,
      );
    }
  }

  /// Pede para a rodada atual parar ANTES do próximo item — nunca cancela
  /// uma chamada já em voo (ela termina normalmente e seu resultado real é
  /// gravado e refletido no relatório). Sem efeito fora de uma execução.
  /// Para a futura execução real dos 104, é a forma segura de pausar no
  /// meio do caminho sem deixar nenhuma chamada pela metade.
  void solicitarInterrupcao() {
    if (!state.executando) return;
    _interrupcaoSolicitada = true;
  }

  Future<void> _executarItem(PatrimonioRepository repositorio, ItemRetificacaoParaExecutar item) async {
    _atualizarItem(item.patrimonioId, (e) => e.copiarCom(status: ItemExecucaoRetificacaoStatus.executando));
    try {
      final resultado = await repositorio.retificarUnidadePatrimonio(item);
      _atualizarItem(
        item.patrimonioId,
        (e) => e.copiarCom(status: ItemExecucaoRetificacaoStatus.sucesso, resultado: resultado),
      );
    } on RetificacaoExecucaoFalhouException catch (falha) {
      _atualizarItem(item.patrimonioId, (e) => e.copiarCom(status: ItemExecucaoRetificacaoStatus.falha, falha: falha));
    } catch (_) {
      // Resultado DESCONHECIDO — nunca presumido como "falhou".
      _atualizarItem(item.patrimonioId, (e) => e.copiarCom(status: ItemExecucaoRetificacaoStatus.resultadoDesconhecido));
    }
  }

  void _atualizarItem(
    String patrimonioId,
    ItemExecucaoRetificacaoEstado Function(ItemExecucaoRetificacaoEstado) atualizar,
  ) {
    final atual = state.itensExecucao[patrimonioId];
    // `null` acontece quando o estado já foi resetado (troca de usuário/
    // `reiniciar`) enquanto esta chamada específica ainda estava em voo —
    // nunca ressuscita um item de uma rodada já descartada.
    if (atual == null) return;
    final novoMapa = Map<String, ItemExecucaoRetificacaoEstado>.from(state.itensExecucao)
      ..[patrimonioId] = atualizar(atual);
    state = RetificacaoState(
      fase: state.fase,
      lote: state.lote,
      loteId: state.loteId,
      justificativa: state.justificativa,
      itensExecucao: novoMapa,
      interrompidaPeloUsuario: state.interrompidaPeloUsuario,
    );
  }

  /// Reenvia a MESMA decisão congelada de um item em
  /// [ItemExecucaoRetificacaoStatus.resultadoDesconhecido] — nunca gera um
  /// novo `operacaoId` (a idempotência do lado do servidor faz o resto).
  Future<void> retryItem(String patrimonioId) async {
    if (state.executando) return;
    final atual = state.itensExecucao[patrimonioId];
    if (atual == null || atual.status != ItemExecucaoRetificacaoStatus.resultadoDesconhecido) return;

    state = RetificacaoState(
      fase: RetificacaoFase.executando,
      lote: state.lote,
      loteId: state.loteId,
      justificativa: state.justificativa,
      itensExecucao: state.itensExecucao,
    );
    await _executarItem(ref.read(patrimonioRepositoryProvider), atual.item);
    if (state.fase == RetificacaoFase.executando) {
      state = RetificacaoState(
        fase: RetificacaoFase.concluida,
        lote: state.lote,
        loteId: state.loteId,
        justificativa: state.justificativa,
        itensExecucao: state.itensExecucao,
        interrompidaPeloUsuario: false,
      );
    }
  }

  /// Descarta o estado inteiro (volta para [RetificacaoFase.semArquivo]) —
  /// só fora de uma execução e sem nenhuma pendência (mesma guarda de
  /// `ComparacaoExecucaoController.reiniciar`).
  void reiniciar() {
    if (state.executando || state.temPendencia) return;
    state = const RetificacaoState();
  }
}
