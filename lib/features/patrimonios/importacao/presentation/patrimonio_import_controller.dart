import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../localizacoes/domain/localizacao.dart';
import '../../../localizacoes/presentation/localizacoes_providers.dart';
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
  /// padrões: com o perfil GETEC ativo, primeiro resolve automaticamente a
  /// gerência GETEC (PROMPT 8.13.1 — nunca depende do usuário escolher
  /// manualmente no dropdown genérico "Destino padrão"; a planilha GETEC
  /// nem tem coluna de setor, então TODOS os bens desta carga pertencem à
  /// GETEC por definição) e só então resolve as localizações únicas da
  /// planilha (seção 15); nos demais casos, vai direto para a análise, como
  /// antes.
  Future<void> avancarAposPadroes() async {
    if (state.perfilAtivo == ImportProfileId.getecLegado) {
      final setores = await ref.read(setoresAtivosParaPatrimonioProvider.future);
      final gerenciaGetec = GetecImportProfile.encontrarGerenciaGetec(setores);
      if (gerenciaGetec == null) {
        state = state.copyWith(
          mensagemErro: () =>
              "Gerência '${GetecImportProfile.siglaGerencia}' não encontrada (ou ambígua/inativa) "
              'entre os setores ativos do Supabase — não é possível continuar com o perfil GETEC.',
        );
        return;
      }
      _historico.add(state.step);
      state = state.copyWith(
        step: ImportStep.resolverLocalizacoes,
        padroes: state.padroes.copyWith(destinoPadraoId: () => gerenciaGetec.id),
      );
      return;
    }
    await analisar();
  }

  // ---------------------------------------------------------------------
  // resolução de localizações (perfil GETEC — seção 15/16)
  // ---------------------------------------------------------------------

  /// Mapeia um texto de localização da planilha para uma `Localizacao`
  /// existente na gerência da carga — `null` remove o mapeamento (volta a
  /// pendente, a menos que também esteja em [localizacoesSemMapeamento]).
  void definirMapeamentoLocalizacao(String textoOriginal, String? localizacaoId) {
    final chave = normalizarTextoComparacao(textoOriginal);
    final novoMapa = Map<String, String>.from(state.mapeamentoLocalizacoes);
    if (localizacaoId == null) {
      novoMapa.remove(chave);
    } else {
      novoMapa[chave] = localizacaoId;
    }
    // escolher uma localização concreta desfaz uma eventual decisão
    // anterior de "importar sem localização" para o mesmo texto.
    final novoSemMapeamento = Set<String>.from(state.localizacoesSemMapeamento)..remove(chave);
    state = state.copyWith(
      mapeamentoLocalizacoes: novoMapa,
      localizacoesSemMapeamento: novoSemMapeamento,
    );
  }

  /// Decisão explícita "Importar sem localização" (seção 32) para um texto
  /// da planilha — nunca aplicado silenciosamente; `false` desfaz a decisão
  /// e volta a linha a pendente.
  void definirImportarSemLocalizacao(String textoOriginal, bool semLocalizacao) {
    final chave = normalizarTextoComparacao(textoOriginal);
    final novoSemMapeamento = Set<String>.from(state.localizacoesSemMapeamento);
    final novoMapa = Map<String, String>.from(state.mapeamentoLocalizacoes);
    if (semLocalizacao) {
      novoSemMapeamento.add(chave);
      novoMapa.remove(chave);
    } else {
      novoSemMapeamento.remove(chave);
    }
    state = state.copyWith(
      mapeamentoLocalizacoes: novoMapa,
      localizacoesSemMapeamento: novoSemMapeamento,
    );
  }

  // ---------------------------------------------------------------------
  // resolução manual de tipos pendentes (PROMPT 8.13)
  // ---------------------------------------------------------------------

  /// Reaplica decisões manuais de tipo tomadas nesta sessão (seções 7/8) —
  /// sobrevive a uma reanálise completa (ex.: usuário volta e reanalisa a
  /// planilha) porque fica em [PatrimonioImportState.mapeamentoTiposPendentes],
  /// indexada pelo número da linha (estável dentro da mesma sessão/arquivo,
  /// já que [linhasBrutas] não muda entre reanálises), nunca no próprio
  /// objeto [ImportRow] (recriado do zero a cada `analisar()`).
  void _reaplicarDecisoesDeTipoPendente(List<ImportRow> linhas) {
    if (state.mapeamentoTiposPendentes.isEmpty) return;
    for (final linha in linhas) {
      final tipoId = state.mapeamentoTiposPendentes[linha.numeroLinha];
      if (tipoId == null) continue;
      linha.tipoIdResolvido = tipoId;
      linha.tipoResolvidoManualmente = true;
      ImportAnalyzer.classificar(linha);
    }
  }

  /// `true` quando a linha está bloqueada especificamente por falta de tipo
  /// (nunca quando havia um texto de tipo que não bateu com o catálogo —
  /// esse caso já tem seu próprio fluxo de sugestão na revisão) — seção 1.
  bool _ehTipoPendente(ImportRow linha) {
    return linha.existenteNoBanco == null &&
        linha.tipoIdResolvido == null &&
        (linha.tipoTexto == null || linha.tipoTexto!.trim().isEmpty);
  }

  /// Atribui manualmente um tipo (id real do catálogo ativo carregado) a UMA
  /// linha bloqueada por tipo vazio — só vale para esta linha/sessão; NUNCA
  /// cria ou altera uma regra do classificador (`tipo_inference.dart`
  /// continua intocado — seção 3). `null` desfaz a decisão e volta a linha a
  /// pendente.
  void definirTipoPendente(ImportRow linha, String? tipoId) {
    linha.tipoIdResolvido = tipoId;
    linha.tipoResolvidoManualmente = tipoId != null;
    ImportAnalyzer.classificar(linha);

    final novoMapa = Map<int, String>.from(state.mapeamentoTiposPendentes);
    if (tipoId == null) {
      novoMapa.remove(linha.numeroLinha);
    } else {
      novoMapa[linha.numeroLinha] = tipoId;
    }
    state = state.copyWith(mapeamentoTiposPendentes: novoMapa, bumpRevisao: true);
  }

  /// Linhas "semelhantes" a [referencia] (mesma descrição normalizada, seção
  /// 4) dentro da fotografia ORIGINAL de pendências de tipo desta sessão —
  /// nunca além dela, e nunca por uma regra global.
  List<ImportRow> linhasSemelhantesPendentes(ImportRow referencia) {
    final chave = _chaveAgrupamentoTipo(referencia);
    if (chave == null) {
      return state.linhas.where((l) => identical(l, referencia)).toList();
    }
    return state.linhas
        .where(
          (l) =>
              state.numerosLinhaTipoPendenteOriginal.contains(l.numeroLinha) &&
              _chaveAgrupamentoTipo(l) == chave,
        )
        .toList();
  }

  /// Aplica [tipoId] a todas as [linhas] de uma vez — só deve ser chamado
  /// depois de o usuário confirmar explicitamente a quantidade afetada na UI
  /// (seção 4: "nunca aplique em lote silenciosamente"). Mesmo mecanismo de
  /// [definirTipoPendente], em lote: fica só nesta sessão, nunca vira regra
  /// do classificador.
  void aplicarTipoEmLote(List<ImportRow> linhas, String tipoId) {
    final novoMapa = Map<int, String>.from(state.mapeamentoTiposPendentes);
    for (final linha in linhas) {
      linha.tipoIdResolvido = tipoId;
      linha.tipoResolvidoManualmente = true;
      ImportAnalyzer.classificar(linha);
      novoMapa[linha.numeroLinha] = tipoId;
    }
    state = state.copyWith(mapeamentoTiposPendentes: novoMapa, bumpRevisao: true);
  }

  /// Botão "Continuar para revisão" do passo de tipos pendentes — nunca
  /// dispara importação nenhuma, só avança um passo do assistente (seção 10:
  /// a gravação real só começa em [confirmarImportacao], numa ação futura e
  /// explícita, sempre depois da revisão).
  ///
  /// PROMPT 8.13.1: proteção também aqui no controller, não só desabilitando
  /// o botão na UI — se algo chamar este método diretamente enquanto ainda
  /// houver `tipoPendenteRestantes > 0`, a chamada é rejeitada (no-op), sem
  /// avançar de passo nem gerar erro.
  void avancarDeTiposPendentesParaRevisao() {
    if (state.tipoPendenteRestantes > 0) return;
    _historico.add(state.step);
    state = state.copyWith(step: ImportStep.revisar);
  }

  String? _chaveAgrupamentoTipo(ImportRow linha) {
    final descricao = linha.descricao;
    if (descricao == null || descricao.trim().isEmpty) return null;
    return normalizarTextoComparacao(descricao);
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
      var localizacoesDaGerencia = const <Localizacao>[];
      if (usaPerfilGetec) {
        final preparo = GetecImportProfile.prepararLinhas(
          linhas: aba.linhas,
          indiceCabecalho: state.indiceCabecalho,
          mapeamento: state.mapeamento,
        );
        linhasBrutas = preparo.linhas;

        // Gerência da carga é fixa (seção 30/31) — vem do destino padrão
        // já configurado, nunca de uma coluna da planilha.
        final gerenciaId = state.padroes.destinoPadraoId;
        if (gerenciaId != null) {
          localizacoesDaGerencia = await ref.read(localizacoesAtivasPorSetorProvider(gerenciaId).future);
        }
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
        _aplicarPosProcessamentoGetec(linhas, tipos, localizacoesDaGerencia);
      }

      _reaplicarDecisoesDeTipoPendente(linhas);

      final pendentesDeTipo = {
        for (final linha in linhas)
          if (_ehTipoPendente(linha)) linha.numeroLinha,
      };

      state = state.copyWith(
        carregando: false,
        linhas: linhas,
        bumpRevisao: true,
        numerosLinhaTipoPendenteOriginal: pendentesDeTipo,
        step: pendentesDeTipo.isEmpty ? ImportStep.revisar : ImportStep.resolverTipos,
      );
    } on AppException catch (e) {
      state = state.copyWith(carregando: false, mensagemErro: () => e.message);
    } catch (_) {
      state = state.copyWith(
        carregando: false,
        mensagemErro: () => 'Não foi possível analisar a planilha. Tente novamente.',
      );
    }
  }

  /// Passo pós-análise exclusivo do perfil GETEC (seções 4/5/8/23): infere
  /// tipo pela descrição quando não há coluna de tipo mapeada e mescla o
  /// tombamento anterior na observação — tudo com uma única passagem pelas
  /// linhas já classificadas, sem chamadas extras ao banco (seção 29).
  /// Reclassifica cada linha uma única vez no final.
  ///
  /// PROMPT 8.12: não marca mais `possivelBaixa` — "BAIXAS LOCALIZADAS" é
  /// uma decisão de negócio conhecida (bem recuperado/relocalizado, nunca
  /// indício de baixa atual), tratada só como "sem localização por regra"
  /// (ver bloco de localização abaixo).
  void _aplicarPosProcessamentoGetec(
    List<ImportRow> linhas,
    List<TipoPatrimonio> tiposAtivos,
    List<Localizacao> localizacoesDaGerencia,
  ) {
    for (final linha in linhas) {
      // Seção 14 da correção de modelagem: a planilha GETEC não tem
      // nenhuma coluna de origem histórica — origem/localização de origem
      // ficam null (nunca um setor fictício "Origem não informada"), e
      // isso não é erro só para cadastros novos desta carga.
      if (linha.existenteNoBanco == null) {
        linha.origemDispensada = true;
      }

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

      // Localização (PROMPT 8.9, seção 32/33): resolvida aqui, fora do
      // ImportAnalyzer genérico. Precedência, nesta ordem — nunca perde o
      // dado silenciosamente:
      //   1. mapeamento manual do usuário (sempre vence, mesmo sobre um
      //      valor "conhecido" abaixo);
      //   2. decisão manual "importar sem localização" do usuário;
      //   3. regra CONHECIDA "isto não é localização" (INTANGÍVEIS,
      //      TI - SOFTWARE, BAIXAS LOCALIZADAS) — null deliberado, nunca
      //      pendência;
      //   4. resolução automática por nome/sigla (com canonicalização de
      //      apelidos conhecidos, ex.: "SITUAÇÃO - PA");
      //   5. nome oficial conhecido mas ausente entre as localizações
      //      ativas carregadas — ERRO explícito (nunca null silencioso);
      //   6. texto desconhecido — pendente, ERRO bloqueante (PROMPT 8.9.1:
      //      exige decisão explícita do usuário antes de poder ser enviada).
      final textoLocalizacao = linha.celulas[ImportColumnField.localizacao];
      linha.localizacaoTexto = textoLocalizacao;
      if (textoLocalizacao != null) {
        final chave = normalizarTextoComparacao(textoLocalizacao);
        final idEscolhido = state.mapeamentoLocalizacoes[chave];
        if (idEscolhido != null) {
          linha.localizacaoIdResolvida = idEscolhido;
        } else if (state.localizacoesSemMapeamento.contains(chave)) {
          // decisão manual do usuário: sem localização — nada a marcar.
        } else if (GetecImportProfile.ehValorSemLocalizacaoConhecido(textoLocalizacao)) {
          linha.localizacaoSemLocalizacaoPorRegra = true;
        } else {
          final resolvidaAutomaticamente = GetecImportProfile.resolverLocalizacao(
            textoLocalizacao,
            localizacoesDaGerencia,
          );
          if (resolvidaAutomaticamente != null) {
            linha.localizacaoIdResolvida = resolvidaAutomaticamente.id;
          } else if (GetecImportProfile.nomeOficialConhecido(textoLocalizacao) != null) {
            linha.localizacaoOficialAusente = true;
          } else {
            linha.localizacaoPendente = true;
          }
        }

        // PROMPT 8.15.1: a nota histórica de "BAIXAS LOCALIZADAS" depende
        // do valor ORIGINAL da planilha (`textoLocalizacao`), nunca do
        // resultado final da localização — precisa sobreviver mesmo quando
        // o usuário mapeia manualmente esse texto para uma localização
        // física concreta (ex.: SITUAÇÃO/SITUADA - PA) nos ramos acima, que
        // então NUNCA passam por `localizacaoSemLocalizacaoPorRegra`. Por
        // isso fica fora/depois da cadeia de precedência acima, não dentro
        // de um dos seus ramos. Idempotente (mesmo mecanismo de
        // [mesclarObservacaoComTombamentoAnterior]): nunca duplica a nota
        // em reanálises.
        if (GetecImportProfile.ehBaixasLocalizadas(textoLocalizacao)) {
          linha.observacao = GetecImportProfile.mesclarObservacaoComRecuperacaoBaixasLocalizadas(
            observacaoBase: linha.observacao,
            eraBaixasLocalizadas: true,
          );
        }
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

  /// Revalidação READ ONLY imediatamente antes da confirmação (PROMPT 8.14,
  /// seção 7): a análise pode ter sido feita minutos antes, e outro
  /// usuário/processo pode ter cadastrado um dos mesmos números nesse
  /// intervalo. Reconsulta em LOTE (nunca uma query por linha — mesmo
  /// método já usado em [analisar], que internamente já fatia em lotes de
  /// até 200 números) só os números que AINDA seriam enviados como
  /// cadastro NOVO (nunca os que já estão marcados "atualizar", que já são
  /// um existente conhecido). Qualquer um que agora já exista no banco é
  /// movido para "já existente" e reclassificado — nunca cadastrado uma
  /// segunda vez. Nenhuma escrita: só leitura.
  Future<void> revalidarAntesDeConfirmar() async {
    final candidatos = state.linhas
        .where((l) => l.seraEnviada && l.status != ImportRowStatus.atualizar)
        .toList();
    final numeros = candidatos.map((l) => l.numeroPatrimonioNormalizado).whereType<String>().toSet().toList();

    state = state.copyWith(revalidando: true);

    var alterados = const <String>[];
    if (numeros.isNotEmpty) {
      final repositorio = ref.read(patrimonioRepositoryProvider);
      final existentesAgora = await repositorio.buscarPorNumerosPatrimonio(numeros);
      final existentesPorNumero = {
        for (final item in existentesAgora)
          if (item.patrimonio.numeroPatrimonio != null) item.patrimonio.numeroPatrimonio!: item,
      };

      final encontrados = <String>[];
      for (final linha in candidatos) {
        final numero = linha.numeroPatrimonioNormalizado;
        if (numero == null) continue;
        final existente = existentesPorNumero[numero];
        if (existente == null) continue;
        linha.existenteNoBanco = existente;
        ImportAnalyzer.classificar(linha);
        encontrados.add(numero);
      }
      alterados = encontrados;
    }

    final novoRevisao = state.revisao + 1;
    state = state.copyWith(
      revalidando: false,
      bumpRevisao: true,
      revalidacaoNumerosQueViraramExistentes: alterados,
      revalidacaoConcluidaNaRevisao: () => novoRevisao,
    );
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
          localizacaoDestinoId: linha.localizacaoIdResolvida,
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
