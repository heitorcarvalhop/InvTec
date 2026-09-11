import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../dashboard/presentation/dashboard_providers.dart';
import '../../data/patrimonio_repository_supabase.dart';
import '../../domain/patrimonio.dart';
import '../../domain/patrimonio_repository.dart';
import '../../domain/tipo_patrimonio.dart';
import '../../presentation/patrimonio_reference_data.dart';
import '../../presentation/patrimonios_controller.dart';
import '../data/spreadsheet_parser.dart';
import '../domain/import_analyzer.dart';
import '../domain/import_column_field.dart';
import '../domain/import_column_mapping.dart';
import '../domain/import_defaults.dart';
import '../domain/import_row.dart';
import '../domain/profiles/getec_import_profile.dart';
import '../domain/profiles/import_profile_id.dart';
import '../domain/profiles/tipo_inference.dart';
import '../domain/text_similarity.dart';
import 'patrimonio_import_state.dart';

/// Máximo de gravações simultâneas no Supabase durante a importação (seção
/// 26): controla a carga sem paralelizar centenas/milhares de chamadas de
/// uma vez.
const importConcorrenciaMaxima = 5;

final patrimonioImportControllerProvider =
    NotifierProvider.autoDispose<PatrimonioImportController, PatrimonioImportState>(
      PatrimonioImportController.new,
    );

/// Controller/estado do assistente de importação (seção 35: "Controller:
/// estado da UI/importação"). Orquestra parser → analyzer → repository,
/// sem nunca fazer INSERT direto: todo cadastro novo passa por
/// `PatrimonioRepository.cadastrar` (RPC `cadastrar_patrimonio`) e toda
/// atualização de existente por `PatrimonioRepository.atualizar` (só
/// metadados).
class PatrimonioImportController extends Notifier<PatrimonioImportState> {
  Uint8List? _bytesArquivo;
  final List<ImportStep> _historico = [];

  @override
  PatrimonioImportState build() => PatrimonioImportState();

  // ---------------------------------------------------------------------
  // 1-2. seleção de arquivo / leitura
  // ---------------------------------------------------------------------

  Future<void> carregarArquivo({required String nomeArquivo, required Uint8List bytes}) async {
    _historico.clear();
    _bytesArquivo = bytes;
    state = PatrimonioImportState(nomeArquivo: nomeArquivo, carregando: true);

    try {
      final arquivo = await SpreadsheetParser.parse(bytes, nomeArquivo);
      final unicaAba = arquivo.abas.length == 1 ? 0 : null;
      state = state.copyWith(
        carregando: false,
        abas: arquivo.abas,
        abaSelecionadaIndice: () => unicaAba,
        indiceCabecalho: unicaAba != null ? _sugerirLinhaCabecalho(arquivo.abas[unicaAba]) : 0,
        step: unicaAba != null ? ImportStep.selecionarCabecalho : ImportStep.selecionarAba,
      );
      if (unicaAba != null) _historico.add(ImportStep.selecionarArquivo);
    } on SpreadsheetParseException catch (e) {
      state = state.copyWith(carregando: false, mensagemErro: () => e.message);
    } catch (_) {
      state = state.copyWith(
        carregando: false,
        mensagemErro: () => 'Erro inesperado ao ler o arquivo.',
      );
    }
  }

  /// Reprocessa o CSV já carregado com um delimitador escolhido
  /// explicitamente pelo usuário (seção 40) — `null` volta a autodetectar.
  Future<void> definirDelimitadorCsv(String? delimitador) async {
    final bytes = _bytesArquivo;
    final nome = state.nomeArquivo;
    if (bytes == null || nome == null) return;

    state = state.copyWith(carregando: true, delimitadorCsv: () => delimitador);
    try {
      final arquivo = await SpreadsheetParser.parse(bytes, nome, delimitadorCsv: delimitador);
      state = state.copyWith(carregando: false, abas: arquivo.abas);
    } on SpreadsheetParseException catch (e) {
      state = state.copyWith(carregando: false, mensagemErro: () => e.message);
    }
  }

  // ---------------------------------------------------------------------
  // 6-7. aba / cabeçalho
  // ---------------------------------------------------------------------

  void selecionarAba(int indice) {
    _historico.add(state.step);
    state = state.copyWith(
      abaSelecionadaIndice: () => indice,
      indiceCabecalho: _sugerirLinhaCabecalho(state.abas[indice]),
      step: ImportStep.selecionarCabecalho,
    );
  }

  void definirIndiceCabecalho(int indice) {
    state = state.copyWith(indiceCabecalho: indice);
  }

  void confirmarCabecalho() {
    _historico.add(state.step);

    // Detecção automática do perfil GETEC (seção 27) — só pelo CONJUNTO de
    // cabeçalhos, nunca pelo nome da aba. Quando detectado, a etapa de
    // mapeamento mostra o banner de reconhecimento em vez de já aplicar a
    // sugestão genérica: o usuário decide explicitamente qual usar.
    if (GetecImportProfile.detectar(state.linhaCabecalho)) {
      state = state.copyWith(
        step: ImportStep.mapearColunas,
        perfilDetectado: () => ImportProfileId.getecLegado,
      );
      return;
    }

    var mapeamento = state.mapeamento;
    if (mapeamento.colunaPorCampo.isEmpty) {
      mapeamento = _sugerirMapeamentoInicial();
    }
    state = state.copyWith(
      step: ImportStep.mapearColunas,
      mapeamento: mapeamento,
      perfilDetectado: () => null,
    );
  }

  // ---------------------------------------------------------------------
  // 8-9. mapeamento de colunas
  // ---------------------------------------------------------------------

  void definirColuna(ImportColumnField campo, int? coluna) {
    state = state.copyWith(mapeamento: state.mapeamento.definindo(campo, coluna));
  }

  /// Botão "Usar configuração sugerida" do banner GETEC (seção 27): aplica
  /// o mapeamento automático das 6 colunas conhecidas e sugere o motivo
  /// padrão (seção 18) — só se o usuário ainda não tiver digitado um.
  void ativarPerfilGetec() {
    final motivoAtual = state.padroes.motivoPadrao;
    state = state.copyWith(
      perfilAtivo: ImportProfileId.getecLegado,
      mapeamento: GetecImportProfile.mapeamentoSugerido(state.linhaCabecalho),
      padroes: (motivoAtual == null || motivoAtual.trim().isEmpty)
          ? state.padroes.copyWith(motivoPadrao: () => GetecImportProfile.motivoPadraoSugerido)
          : state.padroes,
    );
  }

  /// Botão "Configurar manualmente" do banner GETEC: ignora a sugestão e
  /// segue com o comportamento 100% genérico, mesmo os cabeçalhos tendo
  /// sido reconhecidos.
  void ignorarPerfilSugerido() {
    state = state.copyWith(
      perfilAtivo: ImportProfileId.generico,
      mapeamento: state.mapeamento.colunaPorCampo.isEmpty ? _sugerirMapeamentoInicial() : state.mapeamento,
    );
  }

  void avancarParaPadroes() {
    _historico.add(state.step);
    state = state.copyWith(step: ImportStep.configurarPadroes);
  }

  // ---------------------------------------------------------------------
  // 10-11. padrões da importação
  // ---------------------------------------------------------------------

  void definirPadroes(ImportDefaults padroes) {
    state = state.copyWith(padroes: padroes);
  }

  /// Chamado pelo botão "Continuar"/"Analisar planilha" do passo de
  /// padrões: com o perfil GETEC ativo, primeiro resolve as localizações
  /// únicas da planilha (seção 15); nos demais casos, vai direto para a
  /// análise, como antes.
  Future<void> avancarAposPadroes() async {
    if (state.perfilAtivo == ImportProfileId.getecLegado) {
      _historico.add(state.step);
      state = state.copyWith(step: ImportStep.resolverLocalizacoes);
      return;
    }
    await analisar();
  }

  // ---------------------------------------------------------------------
  // resolução de localizações (perfil GETEC — seção 15/16)
  // ---------------------------------------------------------------------

  void definirMapeamentoLocalizacao(String textoOriginal, String? nomeSetor) {
    final chave = normalizarTextoComparacao(textoOriginal);
    final novoMapa = Map<String, String>.from(state.mapeamentoLocalizacoes);
    if (nomeSetor == null) {
      novoMapa.remove(chave);
    } else {
      novoMapa[chave] = nomeSetor;
    }
    state = state.copyWith(mapeamentoLocalizacoes: novoMapa);
  }

  // ---------------------------------------------------------------------
  // navegação genérica
  // ---------------------------------------------------------------------

  void voltar() {
    if (_historico.isEmpty) return;
    state = state.copyWith(step: _historico.removeLast());
  }

  void reiniciar() {
    _historico.clear();
    _bytesArquivo = null;
    state = PatrimonioImportState();
  }

  // ---------------------------------------------------------------------
  // 7-21. análise (mapeamento + padrões → linhas classificadas)
  // ---------------------------------------------------------------------

  Future<void> analisar() async {
    final aba = state.abaSelecionada;
    if (aba == null) return;

    _historico.add(state.step);
    state = state.copyWith(step: ImportStep.revisar, carregando: true, mensagemErro: () => null);

    try {
      final tipos = await ref.read(tiposAtivosProvider.future);
      final setores = await ref.read(setoresAtivosParaPatrimonioProvider.future);
      final repositorio = ref.read(patrimonioRepositoryProvider);

      final usaPerfilGetec = state.perfilAtivo == ImportProfileId.getecLegado;
      var linhasBrutas = aba.linhas;
      var linhasComPossivelBaixa = const <int>{};
      if (usaPerfilGetec) {
        final preparo = GetecImportProfile.prepararLinhas(
          linhas: aba.linhas,
          indiceCabecalho: state.indiceCabecalho,
          mapeamento: state.mapeamento,
          mapeamentoLocalizacoes: state.mapeamentoLocalizacoes,
        );
        linhasBrutas = preparo.linhas;
        linhasComPossivelBaixa = preparo.linhasComPossivelBaixa;
      }

      final numerosCandidatos = _coletarCandidatos(linhasBrutas, ImportColumnField.numeroPatrimonio,
          normalizador: normalizarNumeroPatrimonio);
      final existentes = await repositorio.buscarPorNumerosPatrimonio(numerosCandidatos.toList());
      final existentesPorNumero = {
        for (final item in existentes)
          if (item.patrimonio.numeroPatrimonio != null) item.patrimonio.numeroPatrimonio!: item,
      };

      final numerosSerieCandidatos = _coletarCandidatos(linhasBrutas, ImportColumnField.numeroSerie);
      final numerosSerieExistentes =
          await repositorio.buscarNumerosSerieExistentes(numerosSerieCandidatos.toList());

      final linhas = ImportAnalyzer.analisar(
        linhas: linhasBrutas,
        indiceCabecalho: state.indiceCabecalho,
        mapeamento: state.mapeamento,
        padroes: state.padroes,
        tiposAtivos: tipos,
        setoresAtivos: setores,
        existentesPorNumero: existentesPorNumero,
        numerosSerieExistentesNoBanco: numerosSerieExistentes,
      );

      if (usaPerfilGetec) {
        _aplicarPosProcessamentoGetec(linhas, tipos, linhasComPossivelBaixa);
      }

      state = state.copyWith(carregando: false, linhas: linhas, bumpRevisao: true);
    } on AppException catch (e) {
      state = state.copyWith(carregando: false, mensagemErro: () => e.message);
    } catch (_) {
      state = state.copyWith(
        carregando: false,
        mensagemErro: () => 'Não foi possível analisar a planilha. Tente novamente.',
      );
    }
  }

  /// Passo pós-análise exclusivo do perfil GETEC (seções 4/5/8/23): marca
  /// baixas prováveis, infere tipo pela descrição quando não há coluna de
  /// tipo mapeada e mescla o tombamento anterior na observação — tudo com
  /// uma única passagem pelas linhas já classificadas, sem chamadas extras
  /// ao banco (seção 29). Reclassifica cada linha uma única vez no final.
  void _aplicarPosProcessamentoGetec(
    List<ImportRow> linhas,
    List<TipoPatrimonio> tiposAtivos,
    Set<int> linhasComPossivelBaixa,
  ) {
    for (final linha in linhas) {
      linha.possivelBaixa = linhasComPossivelBaixa.contains(linha.numeroLinha);

      if (linha.existenteNoBanco == null && linha.tipoTexto == null && linha.tipoIdResolvido == null) {
        final inferencia = inferirTipoPorDescricao(linha.descricao);
        final nomeInferido = inferencia.nomeTipo;
        if (inferencia.confianca == InferenciaTipoConfianca.confirmada && nomeInferido != null) {
          final alvo = normalizarTextoComparacao(nomeInferido);
          for (final tipo in tiposAtivos) {
            if (normalizarTextoComparacao(tipo.nome) == alvo) {
              linha.tipoIdResolvido = tipo.id;
              linha.tipoInferidoAutomaticamente = true;
              break;
            }
          }
        }
      }

      final tombamentoAnteriorTexto = linha.celulas[ImportColumnField.tombamentoAnterior];
      if (tombamentoAnteriorTexto != null) {
        final baseObservacao = linha.existenteNoBanco?.patrimonio.observacao ?? linha.observacao;
        linha.observacao = GetecImportProfile.mesclarObservacaoComTombamentoAnterior(
          observacaoBase: baseObservacao,
          tombamentoAnteriorTexto: tombamentoAnteriorTexto,
        );
      }

      ImportAnalyzer.classificar(linha);
    }
  }

  Set<String> _coletarCandidatos(
    List<List<Object?>> linhas,
    ImportColumnField campo, {
    String? Function(String?)? normalizador,
  }) {
    final coluna = state.mapeamento.colunaDe(campo);
    if (coluna == null) return {};
    final resultado = <String>{};
    for (var i = state.indiceCabecalho + 1; i < linhas.length; i++) {
      final linha = linhas[i];
      if (coluna >= linha.length) continue;
      final texto = ImportAnalyzer.celulaParaTexto(linha[coluna]);
      final valor = normalizador != null ? normalizador(texto) : texto;
      if (valor != null && valor.isNotEmpty) resultado.add(valor);
    }
    return resultado;
  }

  // ---------------------------------------------------------------------
  // decisões individuais (seções 13/14/16/19)
  // ---------------------------------------------------------------------

  void definirTipoDaLinha(ImportRow linha, String? tipoId) {
    linha.tipoIdResolvido = tipoId;
    ImportAnalyzer.classificar(linha);
    state = state.copyWith(bumpRevisao: true);
  }

  void definirDestinoDaLinha(ImportRow linha, String? setorId) {
    linha.destinoIdResolvido = setorId;
    ImportAnalyzer.classificar(linha);
    state = state.copyWith(bumpRevisao: true);
  }

  void definirOrigemDaLinha(ImportRow linha, String? setorId) {
    linha.origemIdResolvido = setorId;
    ImportAnalyzer.classificar(linha);
    state = state.copyWith(bumpRevisao: true);
  }

  void decidirExistente(ImportRow linha, ImportExistingAction acao) {
    linha.acaoExistente = acao;
    ImportAnalyzer.classificar(linha);
    state = state.copyWith(bumpRevisao: true);
  }

  void alternarIgnorarLinha(ImportRow linha, bool ignorar) {
    linha.ignoradaManualmente = ignorar;
    final numero = linha.numeroPatrimonioNormalizado;
    if (numero != null) {
      _recalcularGrupoDuplicado(numero);
    } else {
      ImportAnalyzer.classificar(linha);
    }
    state = state.copyWith(bumpRevisao: true);
  }

  void manterPrimeiraOcorrencia(String numeroNormalizado) =>
      _resolverGrupoDuplicado(numeroNormalizado, manterPrimeira: true);

  void manterUltimaOcorrencia(String numeroNormalizado) =>
      _resolverGrupoDuplicado(numeroNormalizado, manterPrimeira: false);

  void ignorarGrupoDuplicado(String numeroNormalizado) =>
      _resolverGrupoDuplicado(numeroNormalizado, ignorarTodas: true);

  void _resolverGrupoDuplicado(
    String numeroNormalizado, {
    bool manterPrimeira = false,
    bool ignorarTodas = false,
  }) {
    final grupo = state.linhas.where((l) => l.numeroPatrimonioNormalizado == numeroNormalizado).toList();
    if (grupo.isEmpty) return;

    if (ignorarTodas) {
      for (final linha in grupo) {
        linha.ignoradaManualmente = true;
      }
    } else {
      final manter = manterPrimeira ? grupo.first : grupo.last;
      for (final linha in grupo) {
        linha.ignoradaManualmente = !identical(linha, manter);
      }
    }
    for (final linha in grupo) {
      linha.duplicadoNoArquivo = false;
      ImportAnalyzer.classificar(linha);
    }
    state = state.copyWith(bumpRevisao: true);
  }

  void _recalcularGrupoDuplicado(String numeroNormalizado) {
    final grupo = state.linhas.where((l) => l.numeroPatrimonioNormalizado == numeroNormalizado).toList();
    final ativos = grupo.where((l) => !l.ignoradaManualmente).length;
    final aindaDuplicado = ativos > 1;
    for (final linha in grupo) {
      linha.duplicadoNoArquivo = aindaDuplicado;
      ImportAnalyzer.classificar(linha);
    }
  }

  // ---------------------------------------------------------------------
  // filtro de revisão (seção 22/23)
  // ---------------------------------------------------------------------

  void filtrar(ImportFiltroRevisao filtro) {
    state = state.copyWith(filtroRevisao: filtro);
  }

  // ---------------------------------------------------------------------
  // 24-31. confirmação / gravação em lotes / cancelamento / retry
  // ---------------------------------------------------------------------

  void solicitarCancelamento() {
    state = state.copyWith(cancelamentoSolicitado: true);
  }

  Future<void> confirmarImportacao() async {
    final aEnviar = state.linhas.where((l) => l.seraEnviada).toList();
    state = state.copyWith(
      step: ImportStep.importando,
      progressoAtual: 0,
      progressoTotal: aEnviar.length,
      cancelamentoSolicitado: false,
    );

    await _executarLote(aEnviar);

    state = state.copyWith(step: ImportStep.resultado, bumpRevisao: true);
    // seção 32: refresh do sistema — sem exigir reiniciar o aplicativo.
    ref.invalidate(dashboardDataProvider);
    ref.invalidate(patrimoniosControllerProvider);
  }

  Future<void> tentarNovamenteFalhas() async {
    final falhas = state.linhas.where((l) => l.resultado?.sucesso == false).toList();
    if (falhas.isEmpty) return;

    state = state.copyWith(carregando: true, bumpRevisao: true);
    final repositorio = ref.read(patrimonioRepositoryProvider);

    // seção 29: revalida antes de tentar de novo — outra pessoa pode ter
    // cadastrado o mesmo número entre uma tentativa e outra.
    final numeros = falhas.map((l) => l.numeroPatrimonioNormalizado).whereType<String>().toSet().toList();
    if (numeros.isNotEmpty) {
      final existentesAgora = await repositorio.buscarPorNumerosPatrimonio(numeros);
      final existentesPorNumero = {
        for (final item in existentesAgora)
          if (item.patrimonio.numeroPatrimonio != null) item.patrimonio.numeroPatrimonio!: item,
      };
      for (final linha in falhas) {
        final numero = linha.numeroPatrimonioNormalizado;
        if (numero != null && linha.existenteNoBanco == null && existentesPorNumero.containsKey(numero)) {
          linha.existenteNoBanco = existentesPorNumero[numero];
        }
      }
    }

    for (final linha in falhas) {
      linha.resultado = null;
      ImportAnalyzer.classificar(linha);
    }
    state = state.copyWith(carregando: false, bumpRevisao: true);

    final aReenviar = falhas.where((l) => l.seraEnviada).toList();
    state = state.copyWith(
      progressoAtual: 0,
      progressoTotal: aReenviar.length,
      cancelamentoSolicitado: false,
    );
    await _executarLote(aReenviar);
    state = state.copyWith(bumpRevisao: true);
  }

  Future<void> _executarLote(List<ImportRow> linhas) async {
    final repositorio = ref.read(patrimonioRepositoryProvider);
    for (var i = 0; i < linhas.length; i += importConcorrenciaMaxima) {
      if (state.cancelamentoSolicitado) break;
      final fim = (i + importConcorrenciaMaxima).clamp(0, linhas.length);
      final lote = linhas.sublist(i, fim);
      await Future.wait(lote.map((linha) => _executarLinha(repositorio, linha)));
      state = state.copyWith(progressoAtual: state.progressoAtual + lote.length, bumpRevisao: true);
    }
  }

  Future<void> _executarLinha(PatrimonioRepository repositorio, ImportRow linha) async {
    try {
      if (linha.status == ImportRowStatus.atualizar) {
        final existente = linha.existenteNoBanco!.patrimonio;
        // Campo ausente/não reconhecido na planilha nunca apaga o valor já
        // cadastrado: só sobrescreve quando a linha realmente trouxe um
        // valor nesse campo. Setor/responsável não entram aqui de jeito
        // nenhum — atualizar() não tem esses parâmetros.
        final atualizado = await repositorio.atualizar(
          id: existente.id,
          numeroPatrimonio: linha.numeroPatrimonio ?? existente.numeroPatrimonio,
          numeroSerie: linha.numeroSerie ?? existente.numeroSerie,
          tipoId: linha.tipoIdResolvido ?? existente.tipoId,
          marca: linha.marca ?? existente.marca,
          modelo: linha.modelo ?? existente.modelo,
          descricao: linha.descricao ?? existente.descricao,
          observacao: linha.observacao ?? existente.observacao,
          dataAquisicao: linha.dataAquisicao ?? existente.dataAquisicao,
        );
        linha.resultado = ImportRowResult(sucesso: true, patrimonioId: atualizado.id);
      } else {
        final criado = await repositorio.cadastrar(
          tipoId: linha.tipoIdResolvido!,
          destinoId: linha.destinoIdResolvido!,
          numeroPatrimonio: linha.numeroPatrimonio,
          numeroSerie: linha.numeroSerie,
          marca: linha.marca,
          modelo: linha.modelo,
          descricao: linha.descricao,
          observacao: linha.observacao,
          dataAquisicao: linha.dataAquisicao,
          origemId: linha.origemIdResolvido,
          responsavelDestino: linha.responsavelDestino,
          motivo: linha.motivo,
          dataMovimentacao: linha.dataEntrada,
        );
        linha.resultado = ImportRowResult(sucesso: true, patrimonioId: criado.id);
      }
    } on AppException catch (e) {
      linha.resultado = ImportRowResult(sucesso: false, mensagemErro: e.message);
    } catch (_) {
      linha.resultado = const ImportRowResult(sucesso: false, mensagemErro: 'Erro inesperado.');
    }
  }

  // ---------------------------------------------------------------------
  // heurísticas iniciais (só sugestões — usuário sempre confirma)
  // ---------------------------------------------------------------------

  int _sugerirLinhaCabecalho(ImportParsedSheet aba) {
    final limite = aba.linhas.length < 10 ? aba.linhas.length : 10;
    var melhorIndice = 0;
    var melhorContagem = -1;
    for (var i = 0; i < limite; i++) {
      final contagem = aba.linhas[i]
          .where((celula) => celula != null && celula.toString().trim().isNotEmpty)
          .length;
      if (contagem > melhorContagem) {
        melhorContagem = contagem;
        melhorIndice = i;
      }
    }
    return melhorIndice;
  }

  ImportColumnMapping _sugerirMapeamentoInicial() {
    var mapeamento = ImportColumnMapping.vazio;
    final usados = <ImportColumnField>{};
    final cabecalho = state.linhaCabecalho;
    for (var i = 0; i < cabecalho.length; i++) {
      final texto = cabecalho[i]?.toString() ?? '';
      final campo = sugerirCampoPorCabecalho(texto);
      if (campo != null && !usados.contains(campo)) {
        mapeamento = mapeamento.definindo(campo, i);
        usados.add(campo);
      }
    }
    return mapeamento;
  }
}
