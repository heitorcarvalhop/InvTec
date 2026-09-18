import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../patrimonios/data/patrimonio_repository_supabase.dart';
import '../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../../patrimonios/presentation/patrimonio_reference_data.dart';
import '../application/sei_documento_analyzer.dart';
import '../application/sei_documento_parser.dart';
import '../data/sei_despacho_parser.dart';
import '../data/sei_pdf_text_extractor.dart';
import '../domain/sei_analise_resultado.dart';

/// Providers isolados (nunca instanciados diretamente pelo controller) para
/// que os testes troquem por dublês via `ProviderScope.overrides` — mesmo
/// padrão já usado para os repositórios (PROMPT 11.1, seção 17: nenhum
/// teste chama produção).
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
  });

  final SeiImportStep step;
  final String? nomeArquivo;
  final int? tamanhoBytes;
  final String? mensagemErro;
  final SeiAnaliseResultado? resultado;
  final SeiFiltroRevisao filtro;

  SeiImportState copyWith({
    SeiImportStep? step,
    String? nomeArquivo,
    int? tamanhoBytes,
    String? Function()? mensagemErro,
    SeiAnaliseResultado? Function()? resultado,
    SeiFiltroRevisao? filtro,
  }) {
    return SeiImportState(
      step: step ?? this.step,
      nomeArquivo: nomeArquivo ?? this.nomeArquivo,
      tamanhoBytes: tamanhoBytes ?? this.tamanhoBytes,
      mensagemErro: mensagemErro != null ? mensagemErro() : this.mensagemErro,
      resultado: resultado != null ? resultado() : this.resultado,
      filtro: filtro ?? this.filtro,
    );
  }
}

final seiImportControllerProvider = NotifierProvider.autoDispose<SeiImportController, SeiImportState>(
  SeiImportController.new,
);

/// Orquestra extração → parsing → cruzamento READ-ONLY (PROMPT 11.1, seção
/// 34) — arquiteturalmente incapaz de registrar uma movimentação: nunca lê
/// `movimentacaoRepositoryProvider`, só `patrimonioRepositoryProvider`
/// (leitura em lote) e os setores ativos já existentes (seção 31). Ler o
/// arquivo, extrair, cruzar e mostrar a revisão — e PARA. "Concluir
/// análise" só fecha o diálogo; não existe um botão que grave nada nesta
/// versão.
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

      // Cruzamento em LOTE (seção 16) — nunca uma consulta por linha, igual
      // ao importador de planilha (`PatrimonioRepository.buscarPorNumerosPatrimonio`
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

      state = state.copyWith(step: SeiImportStep.revisao, resultado: () => resultado, filtro: SeiFiltroRevisao.todos);
    } on SeiPdfLeituraException catch (e) {
      state = state.copyWith(step: SeiImportStep.selecionarArquivo, mensagemErro: () => e.message);
    } catch (_) {
      state = state.copyWith(
        step: SeiImportStep.selecionarArquivo,
        mensagemErro: () => 'Não foi possível analisar o documento. Tente novamente.',
      );
    }
  }

  void filtrar(SeiFiltroRevisao filtro) => state = state.copyWith(filtro: filtro);

  void reiniciar() => state = const SeiImportState();
}
