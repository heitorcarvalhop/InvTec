import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/uuid_v4.dart';
import '../../../auth/domain/profile.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/current_permissions_controller.dart';
import '../../../localizacoes/domain/localizacao.dart';
import '../../../localizacoes/presentation/localizacoes_providers.dart';
import '../../../dashboard/presentation/dashboard_providers.dart';
import '../../data/patrimonio_repository_supabase.dart';
import '../../domain/patrimonio_detalhe.dart';
import '../../domain/patrimonio_repository.dart';
import '../../domain/tipo_patrimonio.dart';
import '../../domain/tombamento_normalizacao.dart';
import '../../presentation/patrimonio_reference_data.dart';
import '../../presentation/patrimonios_controller.dart';
import '../data/spreadsheet_parser.dart';
import '../domain/import_analyzer.dart';
import '../domain/import_column_field.dart';
import '../domain/import_column_mapping.dart';
import '../domain/import_defaults.dart';
import '../domain/import_lote_persistencia.dart';
import '../domain/import_preflight.dart';
import '../domain/import_report_export.dart';
import '../domain/import_row.dart';
import '../domain/patrimonio_comparacao.dart';
import '../domain/patrimonio_decisao.dart';
import '../domain/profiles/getec_import_profile.dart';
import '../domain/profiles/import_profile_id.dart';
import '../domain/profiles/tipo_inference.dart';
import '../domain/text_similarity.dart';
import 'comparacao_execucao_controller.dart';
import 'patrimonio_import_state.dart';

/// mensagem exibida quando [PatrimonioImportController
/// .compararParaAdmin] é chamado por uma sessão sem perfil ADMIN (seção 6:
/// "o novo modo será destinado exclusivamente ao perfil ADMIN"). Pública
/// para os testes.
const mensagemComparacaoRestritaAdmin = 'Este modo de comparação é exclusivo do perfil administrador.';

/// exibida quando [PatrimonioImportController
/// .compararParaAdmin] é chamado enquanto a execução das decisões da
/// comparação ANTERIOR ainda está em andamento ou tem algum item de
/// resultado desconhecido: "não iniciar uma nova comparação enquanto
/// existir uma execução sem resultado definitivo". Pública para os testes.
const mensagemComparacaoBloqueadaPorExecucaoPendente =
    'Há uma execução de alterações em andamento ou pendente de confirmação. '
    'Resolva-a (aguarde terminar, ou tente novamente/consulte o resultado dos itens pendentes) antes de '
    'iniciar uma nova comparação.';

/// Máximo de gravações simultâneas no Supabase durante a importação (seção
/// 26): controla a carga sem paralelizar centenas/milhares de chamadas de
/// uma vez.
const importConcorrenciaMaxima = 5;

/// Resolução PADRÃO (produção) do diretório onde a sessão/relatório de
/// importação em lote são persistidos — diretório de dados do app (sempre
/// gravável, mesmo empacotado via MSIX), nunca a pasta de documentos do
/// usuário. Testes injetam um diretório fixo (ver construtor de
/// [PatrimonioImportController]), sem exercitar `path_provider` de
/// verdade.
Future<String> _diretorioPersistenciaPadrao() async => (await getApplicationSupportDirectory()).path;

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
  /// [importacaoLoteExecucaoHabilitada]/[fileSystem]/
  /// [resolverDiretorioPersistencia] são injetáveis só para teste — mesmo
  /// padrão de `ComparacaoExecucaoController`/`RetificacaoController`
  /// (padrão real, nunca `true` fixo em produção): [importacaoLoteExecucaoHabilitada]
  /// sempre [EnvConfig.importacaoLoteExecucaoHabilitada] por padrão.
  PatrimonioImportController({
    bool Function()? importacaoLoteExecucaoHabilitada,
    FileSystem? fileSystem,
    Future<String> Function()? resolverDiretorioPersistencia,
  }) : _importacaoLoteExecucaoHabilitada =
           importacaoLoteExecucaoHabilitada ?? (() => EnvConfig.importacaoLoteExecucaoHabilitada),
       _fileSystem = fileSystem ?? const LocalFileSystem(),
       _resolverDiretorioPersistencia = resolverDiretorioPersistencia ?? _diretorioPersistenciaPadrao;

  /// GATE OBRIGATÓRIO (não remover nem contornar): enquanto `false`
  /// (padrão — ver [EnvConfig.importacaoLoteExecucaoHabilitada]), NENHUMA
  /// linha desta importação passa por `PatrimonioRepository.cadastrarLote`
  /// (RPC `cadastrar_patrimonio_lote`, migration ainda não confirmada em
  /// produção): [_executarLinha] usa exclusivamente o caminho CONVENCIONAL
  /// de sempre (`PatrimonioRepository.cadastrar`), e nenhum `operacaoId`/
  /// sessão retomável é gerado ou oferecido (ver [confirmarImportacao],
  /// [_carregarLoteAnteriorPendente], [retomarLoteAnterior]) — a UI nunca
  /// chega a oferecer "retomar" porque nada é persistido neste caminho.
  final bool Function() _importacaoLoteExecucaoHabilitada;
  final FileSystem _fileSystem;
  final Future<String> Function() _resolverDiretorioPersistencia;

  /// Exposição pública (read-only) do mesmo GATE acima — para a UI
  /// (`ImportLotePendenteBanner`) decidir se oferece "Retomar" sem ler
  /// [EnvConfig] diretamente (o que ignoraria a flag INJETADA neste
  /// controller em teste — a instância ativa é sempre a fonte de verdade).
  bool get importacaoLoteExecucaoHabilitada => _importacaoLoteExecucaoHabilitada();

  Future<ImportLotePersistencia> _criarPersistenciaLote() async =>
      ImportLotePersistencia(await _resolverDiretorioPersistencia(), fileSystem: _fileSystem);

  Future<ImportReportPersistencia> _criarPersistenciaRelatorio() async =>
      ImportReportPersistencia(await _resolverDiretorioPersistencia(), fileSystem: _fileSystem);

  Uint8List? _bytesArquivo;
  final List<ImportStep> _historico = [];

  /// "as decisões não podem ser transferidas
  /// acidentalmente de um usuário para outro". Mesmo padrão de defesa em
  /// profundidade já usado em `SeiConclusaoLoteController.build()`: este
  /// provider é `.autoDispose` (some ao sair da tela de importação, o que já
  /// devolveria um estado zerado na maioria dos casos), mas login/logout/
  /// troca de usuário SEM desmontar a tela nunca deve deixar as decisões de
  /// uma sessão vazarem para a próxima — `ref.listen` (nunca `ref.watch`,
  /// que reconstruiria isto a cada transição transitória de
  /// `authControllerProvider`) reresolve o estado inteiro só quando o
  /// usuário AUTENTICADO RESOLVIDO realmente muda.
  String? _usuarioConhecido;

  @override
  PatrimonioImportState build() {
    _usuarioConhecido = ref.read(authControllerProvider).value?.profile?.id;
    ref.listen(authControllerProvider, (previous, next) {
      if (!next.hasValue) return;
      final novoUsuario = next.value?.profile?.id;
      if (novoUsuario == _usuarioConhecido) return;
      _usuarioConhecido = novoUsuario;
      _historico.clear();
      _bytesArquivo = null;
      state = PatrimonioImportState();
    });
    // item 4 — persistência local de sessão/progresso: dispara em
    // background (nunca bloqueia `build()`, que é SÍNCRONO); se houver uma
    // sessão incompleta do usuário atual, preenche
    // `PatrimonioImportState.loteAnteriorPendente` assim que resolver, sem
    // sobrescrever nada que o usuário já tenha começado nesta sessão em
    // memória enquanto isso resolvia.
    _carregarLoteAnteriorPendente();
    return PatrimonioImportState();
  }

  /// Verifica, de forma assíncrona (ver [build]), se existe uma sessão de
  /// importação incompleta persistida localmente para o usuário atual —
  /// nunca é a fonte de verdade (a retomada de fato sempre revalida contra
  /// o servidor, ver [retomarLoteAnterior]).
  ///
  /// GATE: enquanto [_importacaoLoteExecucaoHabilitada] for `false`
  /// (padrão), nunca carrega nem oferece nenhuma sessão pendente — na
  /// prática nunca haveria uma mesmo sem este `return` explícito (ver
  /// [confirmarImportacao], que só persiste quando a flag está ligada),
  /// mas o guard fica aqui como segunda camada do GATE OBRIGATÓRIO.
  Future<void> _carregarLoteAnteriorPendente() async {
    if (!_importacaoLoteExecucaoHabilitada()) return;
    final usuarioId = _usuarioConhecido;
    if (usuarioId == null) return;
    try {
      final persistencia = await _criarPersistenciaLote();
      final sessao = persistencia.carregar(usuarioId);
      if (sessao == null || sessao.completo) return;
      // nunca sobrescreve um estado que já avançou (ex.: o usuário já
      // carregou outro arquivo enquanto isto resolvia, ou o usuário mudou
      // — `ref.listen` acima já reseta o estado inteiro nesse caso).
      if (state.step != ImportStep.selecionarArquivo || _usuarioConhecido != usuarioId) return;
      state = state.copyWith(loteAnteriorPendente: () => sessao);
    } catch (_) {
      // puramente auxiliar — ver docstring de `_persistirProgressoLote`.
    }
  }

  // ---------------------------------------------------------------------
  // 1-2. seleção de arquivo / leitura
  // ---------------------------------------------------------------------

  Future<void> carregarArquivo({required String nomeArquivo, required Uint8List bytes}) async {
    _historico.clear();
    _bytesArquivo = bytes;
    // Preserva [PatrimonioImportState.loteAnteriorPendente]: o fluxo de
    // "Retomar" (ver `ImportLotePendenteBanner`) pede ao usuário para
    // re-selecionar o MESMO arquivo original a partir deste mesmo passo —
    // perder a sessão pendente aqui destruiria essa possibilidade antes
    // mesmo da reanálise (ver [retomarLoteAnterior]).
    final loteAnteriorPendente = state.loteAnteriorPendente;
    state = PatrimonioImportState(
      nomeArquivo: nomeArquivo,
      carregando: true,
      loteAnteriorPendente: loteAnteriorPendente,
    );

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
  /// gerência GETEC (nunca depende do usuário escolher manualmente no
  /// dropdown genérico "Destino padrão"; a planilha GETEC nem tem coluna de
  /// setor, então todos os bens desta carga pertencem à GETEC por
  /// definição) e só então resolve as localizações únicas da planilha; nos
  /// demais casos, vai direto para a análise.
  Future<void> avancarAposPadroes() async {
    if (state.perfilAtivo == ImportProfileId.getecLegado) {
      final setores = await ref.read(setoresAtivosParaPatrimonioProvider.future);

      // Preflight formal (seção de pré-condições): mesma checagem que já
      // era feita manualmente abaixo, agora via `ImportPreflight.
      // validarGerenciaUnica` — cobre ausência, ambiguidade E inatividade
      // com mensagens prontas, sem mudar o resultado observável para quem
      // já usa este perfil hoje.
      final preflightGerencia = ImportPreflight.validarGerenciaUnica(
        setores: setores,
        sigla: GetecImportProfile.siglaGerencia,
      );
      if (!preflightGerencia.ok) {
        state = state.copyWith(
          mensagemErro: () => preflightGerencia.issues.map((i) => i.mensagem).join('\n'),
        );
        return;
      }

      final gerenciaGetec = GetecImportProfile.encontrarGerenciaGetec(setores);
      if (gerenciaGetec == null) {
        // Defensivo: o preflight acima já garante exatamente uma gerência
        // ativa com esta sigla, então este ramo não deveria ser alcançável
        // na prática — preservado como segunda camada, nunca removendo a
        // mensagem de erro conhecida.
        state = state.copyWith(
          mensagemErro: () =>
              "Gerência '${GetecImportProfile.siglaGerencia}' não encontrada (ou ambígua/inativa) "
              'entre os setores ativos do Supabase — não é possível continuar com o perfil GETEC.',
        );
        return;
      }

      // NOTA (preflight de nomes de localização — seção da tarefa de
      // generalização): `ImportPreflight.validarNomesEsperados` existe e é
      // testado isoladamente, e [GetecImportProfile.perfil.
      // nomesLocalizacoesOficiais] já expõe a lista dos 15 nomes oficiais —
      // mas NÃO é chamado aqui como gate bloqueante. Testado e confirmado:
      // o comportamento HOJE (intencional, com testes próprios —
      // `localizacaoOficialAusente`) é deixar a planilha avançar e reportar
      // uma localização oficial conhecida mas ausente do catálogo real
      // como ERRO POR LINHA na revisão (bloqueando só aquela linha,
      // permitindo revisar as demais) — nunca um erro global que impede
      // toda a carga de ser analisada. Transformar isso num preflight
      // bloqueante aqui regredira essa granularidade (e quebra os testes
      // que a validam). Ver relatório da tarefa.
      _historico.add(state.step);
      state = state.copyWith(
        step: ImportStep.resolverLocalizacoes,
        padroes: state.padroes.copyWith(destinoPadraoId: () => gerenciaGetec.id),
      );
      return;
    }
    // único ponto de bifurcação do perfil GENÉRICO entre a
    // importação convencional e o modo ADMIN "Comparar e Atualizar": os
    // dois compartilham TODOS os passos anteriores (arquivo, aba,
    // cabeçalho, colunas, padrões) — nunca um segundo assistente.
    if (state.modoComparacaoAdmin) {
      await compararParaAdmin();
    } else {
      await analisar();
    }
  }

  /// DUPLA TRAVA (seção 21 do pedido de Etapa 5 — mesmo motivo documentado
  /// em `_ModoComparacaoAdminToggle`): só ADMIN COM a permissão
  /// `patrimonio.compare_update` pode ativar/desativar o modo "Comparar e
  /// Atualizar" (defesa em profundidade: a UI já esconde o controle de
  /// qualquer sessão sem as duas condições, mas esta checagem garante que
  /// nenhuma chamada direta ao controller o contorne). Sem efeito para
  /// qualquer outra sessão — nunca lança, nunca muda nada.
  void definirModoComparacaoAdmin(bool valor) {
    // Síncrono de propósito (`onChanged` de um Switch não pode ser
    // assíncrono): na prática só é alcançável depois que o próprio toggle
    // já está visível na UI (`_ModoComparacaoAdminToggle` só renderiza com
    // `ref.watch(...hasPermission...)` já resolvido), então
    // `currentPermissionsControllerProvider` já está carregado quando este
    // método roda.
    final perfil = ref.read(authControllerProvider).value?.profile?.perfil;
    final temPermissao =
        ref.read(currentPermissionsControllerProvider).value?.hasPermission('patrimonio.compare_update') ?? false;
    if (perfil != ProfilePerfil.admin || !temPermissao) return;
    state = state.copyWith(modoComparacaoAdmin: valor);
  }

  /// Versão ASSÍNCRONA da dupla trava: espera `currentPermissionsControllerProvider`
  /// resolver antes de checar — evita o falso-negativo de ler `.value` ainda
  /// `null` (AsyncLoading) numa chamada direta ao controller logo após o
  /// login, quando a permissão pode não ter terminado de carregar. Usada
  /// por [compararParaAdmin], que já é `async` e pode pagar esse `await`.
  Future<bool> _podeCompararEAtualizar() async {
    final perfil = ref.read(authControllerProvider).value?.profile?.perfil;
    if (perfil != ProfilePerfil.admin) return false;
    final permissoes = await ref.read(currentPermissionsControllerProvider.future);
    return permissoes.hasPermission('patrimonio.compare_update');
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
  // resolução manual de tipos pendentes
  // ---------------------------------------------------------------------

  /// Reaplica decisões manuais de tipo tomadas nesta sessão — sobrevive a
  /// uma reanálise completa (ex.: usuário volta e reanalisa a
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
  /// dispara importação nenhuma, só avança um passo do assistente (a
  /// gravação real só começa em [confirmarImportacao], sempre depois da
  /// revisão).
  ///
  /// Proteção também aqui no controller, não só desabilitando o botão na
  /// UI — se algo chamar este método diretamente enquanto ainda houver
  /// `tipoPendenteRestantes > 0`, a chamada é rejeitada (no-op).
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

      // Candidatos consultados no banco pela mesma chave de COMPARAÇÃO usada
      // em `ImportAnalyzer` (zeros à esquerda de um tombamento só numérico
      // não fazem parte da identidade — ver tombamento_normalizacao.dart):
      // sem isso, uma planilha com "000502510" nunca encontraria o
      // "502510" já cadastrado no banco.
      final numerosCandidatos = _coletarCandidatos(
        linhasBrutas,
        ImportColumnField.numeroPatrimonio,
        normalizador: (texto) => normalizarTombamentoParaComparacao(texto).chaveComparacao,
      );
      final existentes = await repositorio.buscarPorNumerosPatrimonio(numerosCandidatos.toList());
      final existentesPorNumero = _existentesPorNumeroNormalizado(existentes);

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

  /// modo ADMIN "Comparar e Atualizar": roda a MESMA
  /// [analisar] da importação convencional (mesma leitura de planilha,
  /// mesmo mapeamento, mesma consulta em lote de existentes, mesmo
  /// pós-processamento do perfil ativo — seção 2, "reaproveitar ao
  /// máximo") e, sobre as [PatrimonioImportState.linhas] resultantes, roda
  /// [PatrimonioComparador.comparar] — um SEGUNDO OLHAR, só de leitura,
  /// nunca uma segunda implementação de importador.
  ///
  /// Restrito a ADMIN COM a permissão `patrimonio.compare_update` — DUPLA
  /// TRAVA (seção 21 do pedido de Etapa 5): qualquer sessão sem as duas
  /// condições (perfil, ou sem perfil resolvido, ou sem a permissão) recebe
  /// [mensagemComparacaoRestritaAdmin] em [PatrimonioImportState.
  /// mensagemErro] e NADA é lido/comparado — nem a planilha é analisada.
  ///
  /// Só CONSULTA e COMPARA: nenhuma chamada a `cadastrar`/`atualizar` (nem
  /// aqui, nem dentro de [analisar]/[ImportAnalyzer]/[PatrimonioComparador]
  /// — todos os três são estritamente de leitura). A autorização de
  /// escrita deste modo é tratada à parte, por [ComparacaoExecucaoController].
  Future<void> compararParaAdmin() async {
    if (!await _podeCompararEAtualizar()) {
      state = state.copyWith(mensagemErro: () => mensagemComparacaoRestritaAdmin);
      return;
    }

    // nunca inicia uma nova comparação enquanto a
    // execução das decisões da comparação anterior ainda não tem um
    // resultado definitivo para todo item (executando OU com algum item de
    // resultado desconhecido).
    if (!ref.read(comparacaoExecucaoControllerProvider).podeIniciarNovaExecucao) {
      state = state.copyWith(mensagemErro: () => mensagemComparacaoBloqueadaPorExecucaoPendente);
      return;
    }

    await analisar();
    if (state.mensagemErro != null) return; // `analisar()` já registrou o erro — nada a comparar.

    // cada nova comparação invalida qualquer
    // decisão anterior (nunca reaproveitada de uma planilha/análise
    // diferente) e volta para a lista sem filtro/busca residual de uma
    // sessão anterior.
    state = state.copyWith(
      comparacao: () => PatrimonioComparador.comparar(state.linhas),
      decisoes: const {},
      filtroComparacao: ComparacaoFiltroRevisao.todos,
      buscaNumeroPatrimonio: '',
      step: ImportStep.compararRevisao,
      bumpRevisao: true,
    );
  }

  // ---------------------------------------------------------------------
  // decisões do modo ADMIN "Comparar e Atualizar"
  // ---------------------------------------------------------------------

  /// Todas as [CampoDivergente] elegíveis para decisão agora — só
  /// patrimônios [ClassificacaoComparacao.divergente] (nunca novos, que não
  /// têm cadastro automático — seção 6; nunca bloqueados — seção 7).
  Iterable<(String patrimonioId, CampoDivergente campo)> _campoDivergenteElegiveis() sync* {
    final lote = state.comparacao;
    if (lote == null) return;
    for (final item in lote.itens) {
      if (item.classificacao != ClassificacaoComparacao.divergente) continue;
      final id = item.patrimonioId;
      if (id == null) continue;
      for (final divergencia in item.divergencias) {
        yield (id, divergencia);
      }
    }
  }

  /// Decide UM campo de UM patrimônio (seção 5). Sem efeito se
  /// (patrimonioId, campo) não corresponder a uma divergência real da
  /// comparação atual — nunca cria uma decisão "órfã" que a UI não consiga
  /// mostrar.
  void decidirCampo(String patrimonioId, String campo, DecisaoCampoValor valor) {
    final existe = _campoDivergenteElegiveis().any((e) => e.$1 == patrimonioId && e.$2.campo == campo);
    if (!existe) return;
    final novoMapa = Map<ChaveDecisaoCampo, DecisaoCampoValor>.from(state.decisoes);
    novoMapa[ChaveDecisaoCampo(patrimonioId: patrimonioId, campo: campo)] = valor;
    state = state.copyWith(decisoes: novoMapa, bumpRevisao: true);
  }

  /// "Ignorar todas as divergências de um patrimônio" (seção 5) — só afeta
  /// os campos DAQUELE patrimônio, nunca de outro.
  void ignorarTodosOsCamposDoPatrimonio(String patrimonioId) {
    final novoMapa = Map<ChaveDecisaoCampo, DecisaoCampoValor>.from(state.decisoes);
    for (final (id, campo) in _campoDivergenteElegiveis()) {
      if (id != patrimonioId) continue;
      novoMapa[ChaveDecisaoCampo(patrimonioId: id, campo: campo.campo)] = DecisaoCampoValor.ignorar;
    }
    state = state.copyWith(decisoes: novoMapa, bumpRevisao: true);
  }

  /// Aplica [valor] a todo [ChaveDecisaoCampo] elegível (seção 6) que
  /// passar em [filtro] — devolve quantas decisões foram efetivamente
  /// alteradas, para a UI informar a quantidade afetada (seção 6: "toda
  /// operação em massa deve apresentar a quantidade de decisões
  /// afetadas"). Bloqueados e novos NUNCA entram aqui — `_campoDivergenteElegiveis`
  /// já os exclui estruturalmente.
  int _aplicarEmMassa(DecisaoCampoValor valor, {bool Function(CampoDivergente campo)? filtro}) {
    final novoMapa = Map<ChaveDecisaoCampo, DecisaoCampoValor>.from(state.decisoes);
    var afetadas = 0;
    for (final (id, campo) in _campoDivergenteElegiveis()) {
      if (filtro != null && !filtro(campo)) continue;
      final chave = ChaveDecisaoCampo(patrimonioId: id, campo: campo.campo);
      if (novoMapa[chave] == valor) continue; // já estava neste valor — não conta como "afetada".
      novoMapa[chave] = valor;
      afetadas++;
    }
    if (afetadas > 0) state = state.copyWith(decisoes: novoMapa, bumpRevisao: true);
    return afetadas;
  }

  /// "Selecionar todos os campos elegíveis para atualização" (seção 6).
  int selecionarTodosOsElegiveis() => _aplicarEmMassa(DecisaoCampoValor.aplicar);

  /// "Ignorar todos os campos elegíveis" (seção 6).
  int ignorarTodosOsElegiveis() => _aplicarEmMassa(DecisaoCampoValor.ignorar);

  /// "Selecionar somente divergências de localização" (seção 6) — setor E
  /// localização (a mesma dupla cautela de [PatrimonioComparador], já que
  /// ambos exigem resolução contra um catálogo real).
  int selecionarSomenteLocalizacaoOuSetor() => _aplicarEmMassa(
    DecisaoCampoValor.aplicar,
    filtro: (c) => c.tipo == TipoDivergencia.setor || c.tipo == TipoDivergencia.localizacao,
  );

  /// "Selecionar somente divergências de metadados" (seção 6).
  int selecionarSomenteMetadados() =>
      _aplicarEmMassa(DecisaoCampoValor.aplicar, filtro: (c) => c.tipo == TipoDivergencia.metadado);

  /// "Limpar decisões" (seção 6) — volta TODAS as decisões elegíveis para
  /// [DecisaoCampoValor.pendente].
  int limparDecisoes() => _aplicarEmMassa(DecisaoCampoValor.pendente);

  void definirFiltroComparacao(ComparacaoFiltroRevisao filtro) {
    state = state.copyWith(filtroComparacao: filtro);
  }

  void definirBuscaNumeroPatrimonio(String texto) {
    state = state.copyWith(buscaNumeroPatrimonio: texto);
  }

  /// Navega da lista de revisão (seção 3) para o resumo de decisões (seção
  /// 8) — puramente visual, nenhuma decisão muda.
  void abrirResumoDeDecisoes() {
    _historico.add(state.step);
    state = state.copyWith(step: ImportStep.compararResumo);
  }

  /// Passo pós-análise exclusivo do perfil GETEC (seções 4/5/8/23): infere
  /// tipo pela descrição quando não há coluna de tipo mapeada e mescla o
  /// tombamento anterior na observação — tudo com uma única passagem pelas
  /// linhas já classificadas, sem chamadas extras ao banco. Reclassifica
  /// cada linha uma única vez no final.
  ///
  /// Não marca `possivelBaixa` — "BAIXAS LOCALIZADAS" é uma decisão de
  /// negócio conhecida (bem recuperado/relocalizado, nunca indício de baixa
  /// atual), tratada só como "sem localização por regra" (ver bloco de
  /// localização abaixo).
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

      // Localização: resolvida aqui, fora do ImportAnalyzer genérico.
      // Precedência, nesta ordem — nunca perde o dado silenciosamente:
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
      //   6. texto desconhecido — pendente, ERRO bloqueante (exige decisão
      //      explícita do usuário antes de poder ser enviada).
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

        // A nota de "BAIXAS LOCALIZADAS" depende do valor ORIGINAL da
        // planilha, não do resultado final da localização — por isso fica
        // fora da cadeia de precedência acima. Idempotente: nunca duplica a nota
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

  /// Indexa [existentes] pela mesma chave de COMPARAÇÃO usada em
  /// `linha.numeroPatrimonioNormalizado` (zeros à esquerda de um tombamento
  /// só numérico não fazem parte da identidade — ver
  /// `tombamento_normalizacao.dart`) — nunca pelo texto bruto de
  /// `numero_patrimonio`, para que uma planilha com "000502510" encontre o
  /// "502510" já cadastrado no banco.
  Map<String, PatrimonioDetalhe> _existentesPorNumeroNormalizado(List<PatrimonioDetalhe> existentes) {
    final resultado = <String, PatrimonioDetalhe>{};
    for (final item in existentes) {
      final chave = normalizarTombamentoParaComparacao(item.patrimonio.numeroPatrimonio).chaveComparacao;
      if (chave != null) resultado[chave] = item;
    }
    return resultado;
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

  /// Revalidação READ ONLY imediatamente antes da confirmação: a análise
  /// pode ter sido feita minutos antes, e outro usuário/processo pode ter
  /// cadastrado um dos mesmos números nesse intervalo. Reconsulta em LOTE
  /// (nunca uma query por linha — mesmo
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
      final existentesPorNumero = _existentesPorNumeroNormalizado(existentesAgora);

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
    // item 3 — rastreabilidade estruturada: um `loteId` novo por RODADA de
    // confirmação (nunca por linha), e um `operacaoId` por linha de
    // cadastro NOVO, gerado aqui (nunca dentro de `_executarLinha`, que só
    // reaproveita via `??=`) para já existir no snapshot inicial
    // persistido abaixo (item 4) antes de qualquer chamada de rede.
    //
    // GATE: `operacaoId`/sessão retomável só fazem sentido junto do
    // caminho em LOTE (`cadastrarLote`, idempotente por `operacaoId`) —
    // enquanto [_importacaoLoteExecucaoHabilitada] for `false` (padrão),
    // nenhuma linha recebe `operacaoId` aqui, e [_persistirProgressoLote]
    // abaixo não tem nada para persistir (sempre limpa/no-op nesse caso):
    // o caminho CONVENCIONAL (`cadastrar`, ver [_executarLinha]) continua
    // funcionando exatamente como antes deste recurso existir.
    final usaLote = _importacaoLoteExecucaoHabilitada();
    final loteId = gerarUuidV4();
    final aEnviar = state.linhas.where((l) => l.seraEnviada).toList();
    if (usaLote) {
      for (final linha in aEnviar) {
        if (linha.status != ImportRowStatus.atualizar) {
          linha.operacaoId ??= gerarUuidV4();
        }
      }
    }

    state = state.copyWith(
      step: ImportStep.importando,
      progressoAtual: 0,
      progressoTotal: aEnviar.length,
      cancelamentoSolicitado: false,
      loteIdAtual: () => loteId,
      loteAnteriorPendente: () => null,
    );
    if (usaLote) await _persistirProgressoLote();

    await _executarLote(aEnviar);
    if (usaLote) {
      await _persistirProgressoLote();
    }
    await _persistirRelatorioFinal();

    state = state.copyWith(step: ImportStep.resultado, bumpRevisao: true);
    // seção 32: refresh do sistema — sem exigir reiniciar o aplicativo.
    ref.invalidate(dashboardKpisProvider);
    ref.invalidate(dashboardDistribuicoesProvider);
    ref.invalidate(dashboardMovimentacoesRecentesProvider);
    ref.invalidate(patrimoniosControllerProvider);
  }

  /// Retoma uma sessão de importação incompleta persistida (ver [build] /
  /// [PatrimonioImportState.loteAnteriorPendente]) — só pode ser chamada
  /// depois que o usuário já re-selecionou e reanalisou o MESMO arquivo
  /// original (precisamos das linhas completas, com tipo/destino/etc. já
  /// resolvidos; a persistência local nunca guarda isso, só
  /// numeroLinha/operacaoId/status — ver `import_lote_persistencia.dart`).
  /// Nunca confia no cache: revalida contra o servidor (mesmo padrão de
  /// [revalidarAntesDeConfirmar]) antes de continuar, e processa só as
  /// linhas que a sessão anterior ainda não tinha concluído com sucesso —
  /// reenviando o MESMO `operacaoId` de cada linha (idempotência real,
  /// nunca uma nova tentativa "do zero").
  Future<void> retomarLoteAnterior() async {
    // GATE (segunda camada — ver docstring de [_carregarLoteAnteriorPendente]):
    // nunca executa o caminho em lote enquanto a flag estiver desligada.
    if (!_importacaoLoteExecucaoHabilitada()) return;
    final sessao = state.loteAnteriorPendente;
    if (sessao == null) return;

    await revalidarAntesDeConfirmar();

    final persistidaPorLinha = {for (final l in sessao.linhas) l.numeroLinha: l};
    for (final linha in state.linhas) {
      final persistida = persistidaPorLinha[linha.numeroLinha];
      if (persistida != null) linha.operacaoId = persistida.operacaoId;
    }

    final jaConcluidasComSucesso = sessao.linhas
        .where((l) => l.status == ImportLoteLinhaPersistidaStatus.sucesso)
        .map((l) => l.numeroLinha)
        .toSet();
    final aEnviar = state.linhas
        .where((l) => l.seraEnviada && !jaConcluidasComSucesso.contains(l.numeroLinha))
        .toList();

    state = state.copyWith(
      step: ImportStep.importando,
      progressoAtual: 0,
      progressoTotal: aEnviar.length,
      cancelamentoSolicitado: false,
      loteIdAtual: () => sessao.loteId,
      loteAnteriorPendente: () => null,
    );

    await _executarLote(aEnviar);
    await _persistirProgressoLote();
    await _persistirRelatorioFinal();

    state = state.copyWith(step: ImportStep.resultado, bumpRevisao: true);
    ref.invalidate(dashboardKpisProvider);
    ref.invalidate(dashboardDistribuicoesProvider);
    ref.invalidate(dashboardMovimentacoesRecentesProvider);
    ref.invalidate(patrimoniosControllerProvider);
  }

  /// Descarta a sessão incompleta oferecida para retomada — nunca apaga
  /// nenhum patrimônio já criado (as linhas que já tinham sucesso
  /// permanecem cadastradas); só remove a entrada de persistência local,
  /// para a tela deixar de oferecer "retomar".
  Future<void> descartarLoteAnterior() async {
    final sessao = state.loteAnteriorPendente;
    if (sessao == null) return;
    try {
      final persistencia = await _criarPersistenciaLote();
      await persistencia.limpar(sessao.usuarioId, sessao.loteId);
    } catch (_) {
      // nunca bloqueia a UI por uma falha de armazenamento local — o pior
      // caso é a sessão continuar oferecida numa próxima abertura.
    }
    state = state.copyWith(loteAnteriorPendente: () => null);
  }

  /// Grava (ou limpa, quando já tudo concluído) o progresso da rodada de
  /// confirmação ATUAL em um arquivo JSON próprio (ver docstring de
  /// [ImportLotePersistencia] sobre a decisão de armazenamento) — chamado
  /// antes de iniciar a gravação (snapshot inicial, todas pendentes) e
  /// depois de cada `_executarLote`/retry (snapshot final). Nunca inclui
  /// dados sensíveis de negócio: só numeroLinha/operacaoId/status, o
  /// suficiente para [retomarLoteAnterior] reconciliar contra linhas
  /// recriadas de uma nova análise do MESMO arquivo. Puramente auxiliar:
  /// qualquer falha de armazenamento local (ex.: diretório sem permissão
  /// de escrita) é engolida — a importação REAL nunca pode falhar por
  /// causa da persistência de retomada, só perde a capacidade de oferecer
  /// "retomar" depois. Só chamado quando o GATE em lote está habilitado
  /// (ver [confirmarImportacao]).
  Future<void> _persistirProgressoLote() async {
    final usuarioId = _usuarioConhecido;
    final loteId = state.loteIdAtual;
    if (usuarioId == null || loteId == null) return;

    try {
      final linhasComOperacao = state.linhas.where((l) => l.operacaoId != null).toList();
      final persistencia = await _criarPersistenciaLote();
      if (linhasComOperacao.isEmpty) {
        await persistencia.limpar(usuarioId, loteId);
        return;
      }

      final linhasPersistidas = [
        for (final linha in linhasComOperacao)
          ImportLoteLinhaPersistida(
            numeroLinha: linha.numeroLinha,
            operacaoId: linha.operacaoId!,
            status: linha.resultado == null
                ? ImportLoteLinhaPersistidaStatus.pendente
                : (linha.resultado!.sucesso
                      ? ImportLoteLinhaPersistidaStatus.sucesso
                      : ImportLoteLinhaPersistidaStatus.falha),
          ),
      ];

      if (linhasPersistidas.every((l) => l.status != ImportLoteLinhaPersistidaStatus.pendente)) {
        await persistencia.limpar(usuarioId, loteId);
        return;
      }

      await persistencia.salvar(
        ImportLoteSessaoPersistida(
          loteId: loteId,
          usuarioId: usuarioId,
          nomeArquivo: state.nomeArquivo,
          criadoEm: DateTime.now(),
          linhas: linhasPersistidas,
        ),
      );
    } catch (_) {
      // ver docstring: nunca propaga.
    }
  }

  /// item 5 — relatório de lote persistido/exportável: grava, em um
  /// arquivo JSON próprio, o relatório (linha/número/status/id gerado/
  /// mensagem de erro) de TODAS as linhas desta rodada que já têm um
  /// resultado definitivo — sobrevive a sair da tela, mesmo sem o usuário
  /// exportar o CSV na hora (ver [gerarCsvRelatorioImportacao] para a
  /// exportação em si). Puramente auxiliar, nunca bloqueia a importação
  /// real por uma falha de armazenamento local. Diferente de
  /// [_persistirProgressoLote]: funciona em QUALQUER caminho (convencional
  /// ou em lote) — é só um registro do resultado já obtido, nunca algo que
  /// dispara uma nova chamada de rede.
  Future<void> _persistirRelatorioFinal() async {
    final loteId = state.loteIdAtual;
    if (loteId == null) return;
    try {
      final linhasConcluidas = state.linhas.where((l) => l.resultado != null).toList();
      if (linhasConcluidas.isEmpty) return;
      final persistencia = await _criarPersistenciaRelatorio();
      await persistencia.salvar(
        ImportReport.fromImportRows(
          loteId: loteId,
          nomeArquivo: state.nomeArquivo,
          linhas: linhasConcluidas,
        ),
      );
    } catch (_) {
      // ver docstring de `_persistirProgressoLote`: nunca propaga.
    }
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
      final existentesPorNumero = _existentesPorNumeroNormalizado(existentesAgora);
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
    await _persistirProgressoLote();
    await _persistirRelatorioFinal();
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
          numeroPatrimonio: linha.numeroPatrimonioNormalizado ?? existente.numeroPatrimonio,
          numeroSerie: linha.numeroSerie ?? existente.numeroSerie,
          tipoId: linha.tipoIdResolvido ?? existente.tipoId,
          marca: linha.marca ?? existente.marca,
          modelo: linha.modelo ?? existente.modelo,
          descricao: linha.descricao ?? existente.descricao,
          observacao: linha.observacao ?? existente.observacao,
          dataAquisicao: linha.dataAquisicao ?? existente.dataAquisicao,
        );
        linha.resultado = ImportRowResult(sucesso: true, patrimonioId: atualizado.id);
      } else if (_importacaoLoteExecucaoHabilitada()) {
        // item 3 — rastreabilidade estruturada: cadastro NOVO via
        // `cadastrarLote`, com `operacaoId` (gerado uma única vez por linha
        // — `??=` aqui é só uma segunda camada de segurança, já que
        // `confirmarImportacao`/`retomarLoteAnterior` já garantem isso
        // antes de chamar `_executarLote`) e `loteId` da rodada atual, mais
        // origemArquivo/origemLinha para auditoria. `jaExecutado: true`
        // (retry seguro após uma falha de rede anterior) NUNCA é tratado
        // como erro — é exatamente o resultado esperado.
        //
        // GATE OBRIGATÓRIO: só alcançável com
        // [EnvConfig.importacaoLoteExecucaoHabilitada] ligado (não em
        // produção, até a migration da RPC ser confirmada aplicada lá) —
        // ver docstring de [_importacaoLoteExecucaoHabilitada].
        final operacaoId = linha.operacaoId ??= gerarUuidV4();
        final resultado = await repositorio.cadastrarLote(
          tipoId: linha.tipoIdResolvido!,
          destinoId: linha.destinoIdResolvido!,
          operacaoId: operacaoId,
          loteId: state.loteIdAtual ?? gerarUuidV4(),
          // Valor ENVIADO ao banco é a chave normalizada (sem zeros à
          // esquerda de um tombamento só numérico — ver
          // tombamento_normalizacao.dart), nunca o texto bruto da planilha:
          // `linha.numeroPatrimonio` continua intacto só para exibição e
          // rastreabilidade (relatórios/telas de revisão).
          numeroPatrimonio: linha.numeroPatrimonioNormalizado,
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
          origemArquivo: state.nomeArquivo,
          origemLinha: linha.numeroLinha,
        );
        linha.resultado = ImportRowResult(sucesso: true, patrimonioId: resultado.patrimonio.id);
      } else {
        // Caminho CONVENCIONAL de sempre (GATE desligado — padrão em
        // produção): cadastro novo via `cadastrar` simples, sem
        // `operacaoId`/`loteId`/rastreabilidade por linha — exatamente como
        // funcionava antes do caminho em lote existir. Uma falha de rede
        // aqui é tratada pelo mecanismo de retry já existente
        // ([tentarNovamenteFalhas], que revalida contra o servidor antes
        // de reenviar), nunca pela idempotência por `operacaoId`.
        final resultado = await repositorio.cadastrar(
          tipoId: linha.tipoIdResolvido!,
          destinoId: linha.destinoIdResolvido!,
          // Mesma regra do caminho em lote acima: envia a chave normalizada
          // (sem zeros à esquerda de tombamento só numérico), nunca o texto
          // bruto da planilha.
          numeroPatrimonio: linha.numeroPatrimonioNormalizado,
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
        linha.resultado = ImportRowResult(sucesso: true, patrimonioId: resultado.id);
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
