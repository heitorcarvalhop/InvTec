import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/text_normalization.dart';
import '../../../patrimonios/data/patrimonio_repository_supabase.dart';
import '../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../../patrimonios/presentation/patrimonio_reference_data.dart';
import '../../data/movimentacao_repository_supabase.dart';
import '../../domain/movimentacao_listagem_item.dart';
import '../application/sei_documento_analyzer.dart';
import '../application/sei_documento_parser.dart';
import '../application/sei_duplicidade_checker.dart';
import '../application/sei_plano_execucao_builder.dart';
import '../data/sei_despacho_parser.dart';
import '../data/sei_pdf_text_extractor.dart';
import '../domain/sei_analise_resultado.dart';
import '../domain/sei_decisao_campo.dart';
import '../domain/sei_estagio_preparacao.dart';
import '../domain/sei_item_execucao_estado.dart';
import '../domain/sei_plano_execucao.dart';
import '../domain/sei_validacao_item.dart';

/// Providers isolados (nunca instanciados diretamente pelo controller) para
/// que os testes troquem por dublês via `ProviderScope.overrides` — mesmo
/// padrão já usado para os repositórios.
final seiPdfTextExtractorProvider = Provider<SeiPdfTextExtractor>((ref) => const SeiPdfTextExtractorPdfrx());
final seiDocumentoParserProvider = Provider<SeiDocumentoParser>((ref) => const SeiDeterministicParser());
final seiDocumentoAnalyzerProvider = Provider<SeiDocumentoAnalyzer>((ref) => const SeiDocumentoAnalyzer());

enum SeiImportStep { selecionarArquivo, lendo, revisao }

enum SeiFiltroRevisao { todos, prontos, avisos, bloqueados }

class SeiImportState {
  const SeiImportState({
    this.step = SeiImportStep.selecionarArquivo,
    this.nomeArquivo,
    this.tamanhoBytes,
    this.mensagemErro,
    this.resultado,
    this.filtro = SeiFiltroRevisao.todos,
    this.execucao = const {},
    this.autorizacaoConfirmada = false,
    this.revalidando = false,
  });

  final SeiImportStep step;
  final String? nomeArquivo;
  final int? tamanhoBytes;
  final String? mensagemErro;
  final SeiAnaliseResultado? resultado;
  final SeiFiltroRevisao filtro;

  /// Estado de seleção/confirmação/decisão por linha (chave =
  /// `SeiItemExtraido.linha`). Nunca confundido com o resultado puro da
  /// análise: é decisão do usuário, recalculado só em pontos explícitos
  /// (nova análise, revalidação).
  final Map<int, SeiItemExecucaoEstado> execucao;

  /// Confirmação explícita de que "o procedimento patrimonial foi
  /// efetivamente autorizado" — nunca concedida pela simples seleção do
  /// arquivo ou pelo status PRONTO do parser.
  ///
  /// É uma autorização GERAL do procedimento — NUNCA resolve, sozinha,
  /// nenhuma pendência individual (bloqueio, aviso não conferido,
  /// duplicidade, decisão de localização/responsável pendente). "Documento
  /// autorizado" e "itens efetivamente aptos" (ver [itensAptos]) são
  /// conceitos distintos.
  final bool autorizacaoConfirmada;

  final bool revalidando;

  /// Nenhum destes estágios, isolado ou combinado, habilita nenhuma escrita
  /// nesta versão — ver `SeiEstagioPreparacao`.
  SeiEstagioPreparacao get estagio {
    if (resultado == null) return SeiEstagioPreparacao.documentoInterpretado;
    if (autorizacaoConfirmada) return SeiEstagioPreparacao.autorizado;
    final algumDesatualizado = execucao.values.any((e) => e.desatualizado);
    if (execucao.isNotEmpty && !algumDesatualizado) return SeiEstagioPreparacao.aptoParaExecucao;
    return SeiEstagioPreparacao.patrimoniosConferidos;
  }

  /// Itens tecnicamente APTOS a um lote futuro — independente de já terem
  /// sido selecionados. Distinto de [plano] (que só contém os efetivamente
  /// SELECIONADOS) e de [autorizacaoConfirmada] (uma confirmação geral, não
  /// uma elegibilidade por item).
  List<SeiValidacaoItem> get itensAptos {
    final resultadoAtual = resultado;
    if (resultadoAtual == null) return const [];
    return itensElegiveis(resultado: resultadoAtual, execucao: execucao);
  }

  /// Plano somente leitura dos itens atualmente SELECIONADOS e elegíveis —
  /// recalculado sob demanda, nunca armazenado separadamente (evita os dois
  /// ficarem dessincronizados).
  SeiPlanoExecucao get plano {
    final resultadoAtual = resultado;
    if (resultadoAtual == null) return const SeiPlanoExecucao(itens: []);
    return construirPlanoExecucao(resultado: resultadoAtual, execucao: execucao);
  }

  SeiImportState copyWith({
    SeiImportStep? step,
    String? nomeArquivo,
    int? tamanhoBytes,
    String? Function()? mensagemErro,
    SeiAnaliseResultado? Function()? resultado,
    SeiFiltroRevisao? filtro,
    Map<int, SeiItemExecucaoEstado>? execucao,
    bool? autorizacaoConfirmada,
    bool? revalidando,
  }) {
    return SeiImportState(
      step: step ?? this.step,
      nomeArquivo: nomeArquivo ?? this.nomeArquivo,
      tamanhoBytes: tamanhoBytes ?? this.tamanhoBytes,
      mensagemErro: mensagemErro != null ? mensagemErro() : this.mensagemErro,
      resultado: resultado != null ? resultado() : this.resultado,
      filtro: filtro ?? this.filtro,
      execucao: execucao ?? this.execucao,
      autorizacaoConfirmada: autorizacaoConfirmada ?? this.autorizacaoConfirmada,
      revalidando: revalidando ?? this.revalidando,
    );
  }
}

final seiImportControllerProvider = NotifierProvider.autoDispose<SeiImportController, SeiImportState>(
  SeiImportController.new,
);

/// Orquestra extração → parsing → cruzamento READ-ONLY → checagem de
/// duplicidade READ-ONLY — arquiteturalmente incapaz de registrar uma
/// movimentação: em nenhum método deste arquivo é chamado
/// `MovimentacaoRepository.registrarMovimentacao`, só
/// `patrimonioRepositoryProvider`/`setoresAtivosParaPatrimonioProvider`
/// (leitura em lote) e `movimentacaoRepositoryProvider.listarPorNumeroDocumento`
/// (também leitura, com filtro exato no banco, sem limite arbitrário). Ler
/// o arquivo, extrair, cruzar, checar duplicidade e mostrar a revisão — e
/// PARA. "Concluir análise" só fecha o diálogo; não existe nesta versão
/// nenhum botão que grave nada, mesmo com o documento "autorizado" e todos
/// os itens "aptos".
///
/// LIMITAÇÃO DE IDEMPOTÊNCIA (propriedade do DESENHO, não um bug): a
/// checagem de duplicidade é uma leitura feita ANTES de uma futura escrita,
/// nunca dentro da mesma transação dela. Duas sessões concorrentes podem
/// LER "sem duplicidade" ao mesmo tempo e, se um dia esta versão vier a
/// escrever, ambas poderiam registrar a mesma movimentação — a leitura não
/// é uma trava. A garantia definitiva viria de uma restrição no próprio
/// banco (índice único, ou uma RPC de lote que checasse e escrevesse
/// atomicamente).
class SeiImportController extends Notifier<SeiImportState> {
  @override
  SeiImportState build() => const SeiImportState();

  Future<void> selecionarArquivo({required String nomeArquivo, required Uint8List bytes}) async {
    state = SeiImportState(step: SeiImportStep.lendo, nomeArquivo: nomeArquivo, tamanhoBytes: bytes.length);

    try {
      final extrator = ref.read(seiPdfTextExtractorProvider);
      final lido = await extrator.extrair(bytes);

      final parser = ref.read(seiDocumentoParserProvider);
      final documento = await parser.analisar(
        nomeArquivo: nomeArquivo,
        tamanhoBytes: bytes.length,
        hashSha256: lido.hashSha256,
        textoPorPagina: lido.textoPorPagina,
      );

      // Cruzamento em LOTE — nunca uma consulta por linha, igual ao
      // importador de planilha (`PatrimonioRepository.buscarPorNumerosPatrimonio`
      // já é a mesma consulta reaproveitada de lá).
      final numeros = documento.itens.map((item) => item.numeroPatrimonio).whereType<String>().toSet().toList();
      final patrimonioRepositorio = ref.read(patrimonioRepositoryProvider);
      final encontrados = numeros.isEmpty
          ? const <PatrimonioDetalhe>[]
          : await patrimonioRepositorio.buscarPorNumerosPatrimonio(numeros);
      final patrimoniosPorNumero = {
        for (final detalhe in encontrados)
          if (detalhe.patrimonio.numeroPatrimonio != null) detalhe.patrimonio.numeroPatrimonio!: detalhe,
      };

      final setoresAtivos = await ref.read(setoresAtivosParaPatrimonioProvider.future);

      final analyzer = ref.read(seiDocumentoAnalyzerProvider);
      final resultado = analyzer.analisar(
        documento: documento,
        patrimoniosPorNumero: patrimoniosPorNumero,
        setoresAtivos: setoresAtivos,
      );

      final execucaoInicial = await _construirExecucaoInicial(resultado, patrimoniosPorNumero);

      state = state.copyWith(
        step: SeiImportStep.revisao,
        resultado: () => resultado,
        filtro: SeiFiltroRevisao.todos,
        execucao: execucaoInicial,
        autorizacaoConfirmada: false,
      );
    } on SeiPdfLeituraException catch (e) {
      state = state.copyWith(step: SeiImportStep.selecionarArquivo, mensagemErro: () => e.message);
    } catch (_) {
      state = state.copyWith(
        step: SeiImportStep.selecionarArquivo,
        mensagemErro: () => 'Não foi possível analisar o documento. Tente novamente.',
      );
    }
  }

  /// Revalidação READ-ONLY do estado atual — re-busca patrimônios/setores E
  /// REPETE A CONSULTA COMPLETA de duplicidade (nunca reaproveita o
  /// resultado anterior: outro usuário pode ter registrado uma
  /// movimentação para este mesmo documento entre a análise original e
  /// agora). Uma linha cujo veredito mudou é marcada desatualizada e perde
  /// a seleção (nunca fica selecionável de novo até nova revisão
  /// explícita). A RPC continua sendo a autoridade final no momento de uma
  /// futura escrita — isto só reduz (nunca elimina — ver limitação de
  /// idempotência na doc da classe) a chance de agir sobre dado obsoleto.
  Future<void> revalidar() async {
    final resultadoAnterior = state.resultado;
    final documento = resultadoAnterior?.documento;
    if (documento == null) return;

    state = state.copyWith(revalidando: true);

    try {
      final numeros = documento.itens.map((item) => item.numeroPatrimonio).whereType<String>().toSet().toList();
      final patrimonioRepositorio = ref.read(patrimonioRepositoryProvider);
      final encontrados = numeros.isEmpty
          ? const <PatrimonioDetalhe>[]
          : await patrimonioRepositorio.buscarPorNumerosPatrimonio(numeros);
      final patrimoniosPorNumero = {
        for (final detalhe in encontrados)
          if (detalhe.patrimonio.numeroPatrimonio != null) detalhe.patrimonio.numeroPatrimonio!: detalhe,
      };
      final setoresAtivos = await ref.read(setoresAtivosParaPatrimonioProvider.future);

      final analyzer = ref.read(seiDocumentoAnalyzerProvider);
      final novoResultado = analyzer.analisar(
        documento: documento,
        patrimoniosPorNumero: patrimoniosPorNumero,
        setoresAtivos: setoresAtivos,
      );

      // Consulta de duplicidade INTEIRAMENTE repetida — nunca o resultado
      // computado na análise/revalidação anterior.
      final historico = await _buscarHistoricoDoDocumento(documento.numeroDocumentoSei, patrimoniosPorNumero);

      final antigasPorLinha = {for (final v in resultadoAnterior!.itens) v.item.linha: v};
      final novaExecucao = <int, SeiItemExecucaoEstado>{};

      for (final novaValidacao in novoResultado.itens) {
        final linha = novaValidacao.item.linha;
        final antiga = antigasPorLinha[linha];
        final estadoAnterior = state.execucao[linha] ?? const SeiItemExecucaoEstado();
        final mudou = antiga == null || _snapshot(antiga) != _snapshot(novaValidacao);

        final duplicidade = novaValidacao.patrimonioEncontrado == null
            ? null
            : classificarDuplicidade(
                patrimonioId: novaValidacao.patrimonioEncontrado!.patrimonio.id,
                tipoProposto: novoResultado.documento.tipoMovimentacaoInferido,
                destinoIdProposto: novaValidacao.destino.entidadeEncontrada?.id,
                numeroChamadoProposto: novaValidacao.item.numeroChamado,
                historicoDoDocumento: historico,
              );
        // Uma duplicidade nova (ex.: outro usuário registrou este mesmo
        // item entretanto) também conta como "mudou" — nunca fica escondida
        // atrás de um snapshot que não olhava duplicidade.
        final duplicidadeMudou = duplicidade?.status != estadoAnterior.duplicidade?.status;

        novaExecucao[linha] = estadoAnterior.copyWith(
          desatualizado: mudou || duplicidadeMudou,
          selecionado: (mudou || duplicidadeMudou) ? false : estadoAnterior.selecionado,
          duplicidade: () => duplicidade,
        );
      }

      state = state.copyWith(
        resultado: () => novoResultado,
        execucao: novaExecucao,
        revalidando: false,
        autorizacaoConfirmada: false,
      );
    } catch (_) {
      state = state.copyWith(
        revalidando: false,
        mensagemErro: () => 'Não foi possível revalidar o documento. Tente novamente.',
      );
    }
  }

  /// Alterna a seleção de uma linha para um futuro lote — usa o MESMO
  /// critério de elegibilidade do plano ([itemEstaApto]), para os dois
  /// nunca divergirem. Sempre permite DESSELECIONAR.
  void alternarSelecao(int linha) {
    final resultado = state.resultado;
    if (resultado == null) return;

    SeiValidacaoItem? validacao;
    for (final v in resultado.itens) {
      if (v.item.linha == linha) {
        validacao = v;
        break;
      }
    }
    if (validacao == null) return;

    final atual = state.execucao[linha] ?? const SeiItemExecucaoEstado();
    if (!atual.selecionado && !itemEstaApto(validacao: validacao, estado: atual)) return;

    final novaExecucao = Map<int, SeiItemExecucaoEstado>.from(state.execucao);
    novaExecucao[linha] = atual.copyWith(selecionado: !atual.selecionado);
    state = state.copyWith(execucao: novaExecucao);
  }

  /// "Conferi o número deste patrimônio no documento original". Revogar a
  /// confirmação também tira a linha da seleção — uma linha não conferida
  /// nunca pode entrar em uma futura execução.
  void confirmarAviso(int linha, bool confirmado) {
    _atualizarLinha(
      linha,
      (atual) => atual.copyWith(avisoConfirmado: confirmado, selecionado: confirmado ? atual.selecionado : false),
    );
  }

  /// Decisão EXPLÍCITA de localização de destino — [localizacaoId] deve ser
  /// uma localização real e ATIVA do setor de destino (a UI só oferece
  /// essas, nunca inventa). Nunca chamado implicitamente pela autorização
  /// geral do documento.
  void definirLocalizacaoDestino(int linha, {required String localizacaoId, required String localizacaoNome}) {
    _atualizarLinha(
      linha,
      (atual) => atual.copyWith(
        decisaoLocalizacao: SeiDecisaoCampo.definido,
        localizacaoDestinoId: () => localizacaoId,
        localizacaoDestinoNome: () => localizacaoNome,
        // uma decisão nova sobre destino invalida uma seleção anterior —
        // força nova conferência antes de voltar a poder selecionar.
        selecionado: false,
      ),
    );
  }

  /// Confirmação EXPLÍCITA de que a localização de destino fica sem
  /// informação — distinto de nunca ter decidido
  /// ([SeiDecisaoCampo.pendente]).
  void confirmarSemLocalizacao(int linha) {
    _atualizarLinha(
      linha,
      (atual) => atual.copyWith(
        decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
        localizacaoDestinoId: () => null,
        localizacaoDestinoNome: () => null,
        selecionado: false,
      ),
    );
  }

  /// Decisão EXPLÍCITA de responsável de destino — texto vazio/só espaço
  /// não conta como definido (usar [confirmarSemResponsavel] para isso).
  void definirResponsavelDestino(int linha, String responsavel) {
    final normalizado = nullIfBlank(responsavel);
    _atualizarLinha(
      linha,
      (atual) => atual.copyWith(
        decisaoResponsavel: normalizado == null ? SeiDecisaoCampo.pendente : SeiDecisaoCampo.definido,
        responsavelDestino: () => normalizado,
        selecionado: false,
      ),
    );
  }

  /// Confirmação EXPLÍCITA de que o responsável de destino fica sem
  /// informação.
  void confirmarSemResponsavel(int linha) {
    _atualizarLinha(
      linha,
      (atual) => atual.copyWith(
        decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
        responsavelDestino: () => null,
        selecionado: false,
      ),
    );
  }

  /// O aviso "Este documento foi analisado com sucesso. Confirme que o
  /// procedimento patrimonial foi efetivamente autorizado…" precisa de uma
  /// ação explícita do usuário — nunca concedido pela simples seleção do
  /// arquivo ou pelo status PRONTO do parser. Mesmo confirmado, nenhum
  /// botão de escrita fica disponível nesta versão, e nenhuma pendência
  /// individual é resolvida por isso.
  void confirmarAutorizacao(bool valor) => state = state.copyWith(autorizacaoConfirmada: valor);

  void filtrar(SeiFiltroRevisao filtro) => state = state.copyWith(filtro: filtro);

  void reiniciar() => state = const SeiImportState();

  void _atualizarLinha(int linha, SeiItemExecucaoEstado Function(SeiItemExecucaoEstado atual) atualizar) {
    final novaExecucao = Map<int, SeiItemExecucaoEstado>.from(state.execucao);
    final atual = novaExecucao[linha] ?? const SeiItemExecucaoEstado();
    novaExecucao[linha] = atualizar(atual);
    state = state.copyWith(execucao: novaExecucao);
  }

  Future<Map<int, SeiItemExecucaoEstado>> _construirExecucaoInicial(
    SeiAnaliseResultado resultado,
    Map<String, PatrimonioDetalhe> patrimoniosPorNumero,
  ) async {
    final historico = await _buscarHistoricoDoDocumento(resultado.documento.numeroDocumentoSei, patrimoniosPorNumero);

    return {
      for (final validacao in resultado.itens)
        validacao.item.linha: SeiItemExecucaoEstado(
          duplicidade: validacao.patrimonioEncontrado == null
              ? null
              : classificarDuplicidade(
                  patrimonioId: validacao.patrimonioEncontrado!.patrimonio.id,
                  tipoProposto: resultado.documento.tipoMovimentacaoInferido,
                  destinoIdProposto: validacao.destino.entidadeEncontrada?.id,
                  numeroChamadoProposto: validacao.item.numeroChamado,
                  historicoDoDocumento: historico,
                ),
        ),
    };
  }

  /// Única leitura em lote do histórico relacionado a este documento SEI
  /// (nunca uma consulta por item) — usa
  /// `MovimentacaoRepository.listarPorNumeroDocumento`, que filtra
  /// `numero_documento = X` diretamente no banco (nunca a busca OR genérica
  /// de `.listar`) e pagina internamente até o total real. Esta é a ÚNICA
  /// leitura que este controller faz em `MovimentacaoRepository`, e é
  /// sempre `.listarPorNumeroDocumento` — nunca `.registrarMovimentacao`.
  Future<List<MovimentacaoListagemItem>> _buscarHistoricoDoDocumento(
    String? numeroDocumentoSei,
    Map<String, PatrimonioDetalhe> patrimoniosPorNumero,
  ) async {
    final numero = numeroDocumentoSei?.trim();
    if (numero == null || numero.isEmpty) return const [];

    final patrimonioIds = patrimoniosPorNumero.values.map((d) => d.patrimonio.id).toList();
    final repositorio = ref.read(movimentacaoRepositoryProvider);
    return repositorio.listarPorNumeroDocumento(numero, patrimonioIds: patrimonioIds);
  }
}

/// Retrato comparável de uma linha, usado só para detectar mudança na
/// revalidação — dois retratos iguais (`==` de record) significam "nada
/// relevante mudou desde a análise anterior".
(SeiStatusLinha, dynamic, dynamic, dynamic, String?, dynamic) _snapshot(SeiValidacaoItem v) => (
  v.status,
  v.patrimonioEncontrado?.patrimonio.status,
  v.patrimonioEncontrado?.patrimonio.setorAtualId,
  v.patrimonioEncontrado?.patrimonio.localizacaoAtualId,
  v.patrimonioEncontrado?.patrimonio.responsavelAtual,
  v.destino.entidadeEncontrada?.id,
);
