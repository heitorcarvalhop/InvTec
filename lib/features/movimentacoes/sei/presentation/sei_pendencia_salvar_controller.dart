import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sei_documento_pendencia_builder.dart';
import '../data/documentos_sei_repository_supabase.dart';
import '../domain/sei_analise_resultado.dart';
import '../domain/sei_documento_pendente.dart';
import '../domain/sei_item_execucao_estado.dart';
import '../domain/sei_pendencia_exceptions.dart';

/// PROMPT 11.3 — "Salvar como pendência": SEPARADO de `SeiImportController`
/// de propósito (mesmo padrão de isolamento de `SeiPlanoExecucaoBuilder`
/// vs. o restante do assistente) para que a garantia "nunca registra uma
/// movimentação" permaneça auditável olhando só para este arquivo — nenhum
/// método aqui lê `MovimentacaoRepository`, só
/// `DocumentosSeiRepository.buscarPossivelDuplicata`/`salvarRascunho`.
/// Importar e salvar um despacho SEMPRE cria uma solicitação PENDENTE;
/// nunca altera um patrimônio.
enum SeiSalvarPendenciaStatus {
  ocioso,
  verificandoDuplicidade,

  /// Seção 5: já existe ao menos um documento com o mesmo número SEI (e,
  /// quando informado, o mesmo processo) — nunca bloqueado sozinho; exige
  /// confirmação explícita do usuário (`confirmarApesarDeDuplicata`) para
  /// prosseguir mesmo assim.
  aguardandoConfirmacaoDuplicidade,
  salvando,
  sucesso,
  erro,
}

class SeiSalvarPendenciaState {
  const SeiSalvarPendenciaState({
    this.status = SeiSalvarPendenciaStatus.ocioso,
    this.duplicatas = const [],
    this.documentoSalvo,
    this.mensagemErro,
  });

  final SeiSalvarPendenciaStatus status;
  final List<SeiDocumentoPendente> duplicatas;
  final SeiDocumentoPendente? documentoSalvo;
  final String? mensagemErro;

  SeiSalvarPendenciaState copyWith({
    SeiSalvarPendenciaStatus? status,
    List<SeiDocumentoPendente>? duplicatas,
    SeiDocumentoPendente? Function()? documentoSalvo,
    String? Function()? mensagemErro,
  }) {
    return SeiSalvarPendenciaState(
      status: status ?? this.status,
      duplicatas: duplicatas ?? this.duplicatas,
      documentoSalvo: documentoSalvo != null ? documentoSalvo() : this.documentoSalvo,
      mensagemErro: mensagemErro != null ? mensagemErro() : this.mensagemErro,
    );
  }
}

final seiPendenciaSalvarControllerProvider =
    NotifierProvider.autoDispose<SeiPendenciaSalvarController, SeiSalvarPendenciaState>(
      SeiPendenciaSalvarController.new,
    );

class SeiPendenciaSalvarController extends Notifier<SeiSalvarPendenciaState> {
  SeiDocumentoPendenteRascunho? _rascunhoPendente;

  @override
  SeiSalvarPendenciaState build() => const SeiSalvarPendenciaState();

  /// Seção 5: checagem READ-ONLY de possível duplicata pelo número do
  /// documento SEI (nunca pelo hash) ANTES de salvar. Sem número de
  /// documento SEI reconhecido, não há o que comparar — segue direto para
  /// salvar (o usuário já vê essa ausência na revisão da análise).
  Future<void> salvar({
    required SeiAnaliseResultado resultado,
    required Map<int, SeiItemExecucaoEstado> execucao,
  }) async {
    final rascunho = construirDocumentoPendenteRascunho(resultado: resultado, execucao: execucao);
    if (rascunho == null) {
      state = state.copyWith(
        status: SeiSalvarPendenciaStatus.erro,
        mensagemErro: () =>
            'Não foi possível identificar o tipo de operação deste documento — só despachos de '
            'TRANSFERENCIA são reconhecidos nesta versão. Não é possível salvar como pendência.',
      );
      return;
    }

    _rascunhoPendente = rascunho;
    final numero = rascunho.numeroDocumentoSei?.trim();
    if (numero == null || numero.isEmpty) {
      await _salvarDefinitivo(rascunho);
      return;
    }

    state = state.copyWith(status: SeiSalvarPendenciaStatus.verificandoDuplicidade);
    try {
      final repositorio = ref.read(documentosSeiRepositoryProvider);
      final duplicatas = await repositorio.buscarPossivelDuplicata(
        numeroDocumentoSei: numero,
        numeroProcesso: rascunho.numeroProcesso,
      );
      if (duplicatas.isNotEmpty) {
        state = state.copyWith(
          status: SeiSalvarPendenciaStatus.aguardandoConfirmacaoDuplicidade,
          duplicatas: duplicatas,
        );
        return;
      }
      await _salvarDefinitivo(rascunho);
    } catch (_) {
      state = state.copyWith(
        status: SeiSalvarPendenciaStatus.erro,
        mensagemErro: () => 'Não foi possível checar documentos já existentes. Tente novamente.',
      );
    }
  }

  /// Seção 5: prosseguir MESMO ASSIM depois de ver a lista de possíveis
  /// duplicatas — nunca automático.
  Future<void> confirmarApesarDeDuplicata() async {
    final rascunho = _rascunhoPendente;
    if (rascunho == null) return;
    await _salvarDefinitivo(rascunho, confirmarDuplicata: true);
  }

  void reiniciar() {
    _rascunhoPendente = null;
    state = const SeiSalvarPendenciaState();
  }

  Future<void> _salvarDefinitivo(SeiDocumentoPendenteRascunho rascunho, {bool confirmarDuplicata = false}) async {
    state = state.copyWith(status: SeiSalvarPendenciaStatus.salvando);
    try {
      final repositorio = ref.read(documentosSeiRepositoryProvider);
      final documento = await repositorio.salvarRascunho(rascunho, confirmarDuplicata: confirmarDuplicata);
      state = state.copyWith(status: SeiSalvarPendenciaStatus.sucesso, documentoSalvo: () => documento);
    } on SeiDocumentoDuplicadoException {
      // PROMPT 11.3.1, seção 8 — a corrida real: a checagem em `salvar()`
      // não encontrou nada, mas outra sessão criou o documento entre essa
      // leitura e esta escrita. O banco (não o cliente) barrou — relê as
      // duplicatas e volta para a mesma confirmação explícita, nunca falha
      // silenciosamente nem sobrescreve.
      try {
        final repositorio = ref.read(documentosSeiRepositoryProvider);
        final duplicatas = await repositorio.buscarPossivelDuplicata(
          numeroDocumentoSei: rascunho.numeroDocumentoSei!,
          numeroProcesso: rascunho.numeroProcesso,
        );
        state = state.copyWith(
          status: SeiSalvarPendenciaStatus.aguardandoConfirmacaoDuplicidade,
          duplicatas: duplicatas,
        );
      } catch (_) {
        state = state.copyWith(
          status: SeiSalvarPendenciaStatus.erro,
          mensagemErro: () => 'Já existe um documento pendente com este número. Tente novamente.',
        );
      }
    } catch (_) {
      state = state.copyWith(
        status: SeiSalvarPendenciaStatus.erro,
        mensagemErro: () => 'Não foi possível salvar a pendência. Tente novamente.',
      );
    }
  }
}
