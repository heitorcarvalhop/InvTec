import '../data/spreadsheet_parser.dart';
import '../domain/import_column_mapping.dart';
import '../domain/import_defaults.dart';
import '../domain/import_row.dart';
import '../domain/import_summary.dart';
import '../domain/profiles/import_profile_id.dart';

/// Passos do assistente de importação (seção 3) — sempre nesta ordem;
/// nunca importa automaticamente ao selecionar o arquivo. [resolverLocalizacoes]
/// só é visitado quando um perfil com localizações a resolver (hoje, só o
/// GETEC) está ativo — ver [PatrimonioImportState.perfilAtivo].
enum ImportStep {
  selecionarArquivo,
  selecionarAba,
  selecionarCabecalho,
  mapearColunas,
  configurarPadroes,
  resolverLocalizacoes,
  resolverTipos,
  revisar,
  importando,
  resultado,
}

/// Filtro do passo de revisão (seção 22/23) — "duplicados" não é um
/// [ImportRowStatus] próprio (é um sub-caso de erro), por isso é um enum
/// separado só para a UI.
enum ImportFiltroRevisao { todos, prontos, avisos, erros, duplicados, existentes, atualizar, ignorados }

extension ImportFiltroRevisaoLabel on ImportFiltroRevisao {
  String get label {
    switch (this) {
      case ImportFiltroRevisao.todos:
        return 'Todos';
      case ImportFiltroRevisao.prontos:
        // PROMPT 8.14: rótulo "Novos" (a linguagem que o usuário reconhece —
        // "será cadastrado como novo patrimônio"), sem renomear o valor do
        // enum nem mudar seu predicado (continua só `status == pronto`;
        // linhas com aviso têm seu próprio filtro "Avisos", já que também
        // seriam enviadas mas merecem inspeção separada).
        return 'Novos';
      case ImportFiltroRevisao.avisos:
        return 'Avisos';
      case ImportFiltroRevisao.erros:
        return 'Erros';
      case ImportFiltroRevisao.duplicados:
        return 'Duplicados';
      case ImportFiltroRevisao.existentes:
        return 'Já existentes';
      case ImportFiltroRevisao.atualizar:
        return 'Atualizar';
      case ImportFiltroRevisao.ignorados:
        return 'Ignorados';
    }
  }
}

List<ImportRow> aplicarFiltroRevisao(List<ImportRow> linhas, ImportFiltroRevisao filtro) {
  switch (filtro) {
    case ImportFiltroRevisao.todos:
      return linhas;
    case ImportFiltroRevisao.prontos:
      return linhas.where((l) => l.status == ImportRowStatus.pronto).toList();
    case ImportFiltroRevisao.avisos:
      return linhas.where((l) => l.status == ImportRowStatus.aviso).toList();
    case ImportFiltroRevisao.erros:
      return linhas.where((l) => l.status == ImportRowStatus.erro && !l.duplicadoNoArquivo).toList();
    case ImportFiltroRevisao.duplicados:
      return linhas.where((l) => l.duplicadoNoArquivo).toList();
    case ImportFiltroRevisao.existentes:
      return linhas.where((l) => l.status == ImportRowStatus.existente).toList();
    case ImportFiltroRevisao.atualizar:
      return linhas.where((l) => l.status == ImportRowStatus.atualizar).toList();
    case ImportFiltroRevisao.ignorados:
      return linhas.where((l) => l.status == ImportRowStatus.ignorado).toList();
  }
}

/// Estado completo do assistente — uma única classe mutável-por-substituição
/// (nunca mutamos [PatrimonioImportState] em si; sempre `copyWith`). As
/// [linhas] dentro dela, porém, SÃO mutadas em memória (ver [ImportRow]) por
/// razão de desempenho com milhares de linhas; [revisao] é incrementado a
/// cada mutação para o Riverpod detectar que precisa notificar os widgets.
class PatrimonioImportState {
  PatrimonioImportState({
    this.step = ImportStep.selecionarArquivo,
    this.nomeArquivo,
    this.abas = const [],
    this.abaSelecionadaIndice,
    this.indiceCabecalho = 0,
    this.delimitadorCsv,
    this.mapeamento = ImportColumnMapping.vazio,
    ImportDefaults? padroes,
    this.linhas = const [],
    this.carregando = false,
    this.mensagemErro,
    this.progressoAtual = 0,
    this.progressoTotal = 0,
    this.cancelamentoSolicitado = false,
    this.filtroRevisao = ImportFiltroRevisao.todos,
    this.revisao = 0,
    this.perfilDetectado,
    this.perfilAtivo = ImportProfileId.generico,
    this.mapeamentoLocalizacoes = const {},
    this.localizacoesSemMapeamento = const {},
    this.mapeamentoTiposPendentes = const {},
    this.numerosLinhaTipoPendenteOriginal = const {},
    this.revalidando = false,
    this.revalidacaoConcluidaNaRevisao,
    this.revalidacaoNumerosQueViraramExistentes = const [],
  }) : padroes = padroes ?? ImportDefaults();

  final ImportStep step;
  final String? nomeArquivo;
  final List<ImportParsedSheet> abas;
  final int? abaSelecionadaIndice;
  final int indiceCabecalho;
  final String? delimitadorCsv;
  final ImportColumnMapping mapeamento;
  final ImportDefaults padroes;
  final List<ImportRow> linhas;
  final bool carregando;
  final String? mensagemErro;
  final int progressoAtual;
  final int progressoTotal;
  final bool cancelamentoSolicitado;
  final ImportFiltroRevisao filtroRevisao;
  final int revisao;

  /// Perfil detectado automaticamente pelos cabeçalhos (seção 27) — sempre
  /// informativo, independente de o usuário ter ativado ou não.
  final ImportProfileId? perfilDetectado;

  /// Perfil efetivamente em uso nesta importação — só muda para algo além
  /// de [ImportProfileId.generico] quando o usuário confirma explicitamente
  /// (seção 27: "não esconder do usuário que um perfil foi ativado").
  final ImportProfileId perfilAtivo;

  /// Localização da planilha (texto normalizado) → id da `Localizacao`
  /// escolhida pelo usuário no passo de localizações, dentro da gerência
  /// fixa da carga (seção 15/16/33) — nunca criação automática de
  /// localização.
  final Map<String, String> mapeamentoLocalizacoes;

  /// Localizações da planilha (texto normalizado) para as quais o usuário
  /// decidiu explicitamente "importar sem localização" (seção 32) —
  /// distinto de "ainda não decidido" (que fica pendente/aviso).
  final Set<String> localizacoesSemMapeamento;

  /// Decisões manuais de tipo tomadas na tela de pendências (PROMPT 8.13) —
  /// número da linha original (estável dentro da mesma sessão/arquivo,
  /// diferente do texto de localização) → id do tipo escolhido. Reaplicada a
  /// cada `analisar()` para sobreviver a uma reanálise completa, já que
  /// [ImportRow] é recriado do zero a cada chamada. Nunca vira regra do
  /// classificador — só afeta linhas desta sessão.
  final Map<int, String> mapeamentoTiposPendentes;

  /// Fotografia (número da linha) de quais linhas estavam bloqueadas
  /// especificamente por "tipo vazio" na análise que abriu a tela de
  /// pendências — usada para calcular o progresso (seção 9) e para o
  /// agrupamento de "Aplicar aos semelhantes" (seção 4), sem incluir linhas
  /// que nunca estiveram pendentes.
  final Set<int> numerosLinhaTipoPendenteOriginal;

  /// Linhas que fazem parte da fotografia de pendências de tipo desta
  /// análise — a lista mostrada na tela de resolução manual.
  List<ImportRow> get linhasTipoPendente =>
      linhas.where((l) => numerosLinhaTipoPendenteOriginal.contains(l.numeroLinha)).toList();

  int get totalTipoPendente => numerosLinhaTipoPendenteOriginal.length;

  int get tipoPendenteRestantes =>
      linhasTipoPendente.where((l) => l.tipoIdResolvido == null).length;

  int get tipoPendenteResolvidos => totalTipoPendente - tipoPendenteRestantes;

  /// `true` enquanto uma revalidação contra o Supabase real está em
  /// andamento (PROMPT 8.14, seção 7) — usado para mostrar um spinner e
  /// evitar clique duplo no botão de importar.
  final bool revalidando;

  /// Valor de [revisao] no momento em que a última revalidação terminou —
  /// `null` antes da primeira revalidação. Comparar com [revisao] atual diz
  /// se a revalidação ainda é válida para o estado ATUAL das linhas: como
  /// [revisao] é incrementado a cada mutação (inclusive pela própria
  /// revalidação), qualquer decisão manual tomada DEPOIS invalida a
  /// revalidação automaticamente, sem precisar de um flag separado para
  /// "ficou desatualizada".
  final int? revalidacaoConcluidaNaRevisao;

  /// `true` quando a revalidação mais recente está atualizada em relação ao
  /// estado atual das linhas (seção 9: "revalidação contra banco
  /// concluída" é uma das condições da barreira de importação).
  bool get revalidacaoValidaParaEstadoAtual => revalidacaoConcluidaNaRevisao == revisao;

  /// Números patrimoniais que a última revalidação encontrou já existindo
  /// no banco — eram "novos" na análise original mas, entre a análise e a
  /// confirmação, alguém cadastrou o mesmo número (PROMPT 8.14, seção 7).
  /// Vazio quando a revalidação não encontrou nenhuma mudança.
  final List<String> revalidacaoNumerosQueViraramExistentes;

  ImportParsedSheet? get abaSelecionada =>
      abaSelecionadaIndice == null ? null : abas[abaSelecionadaIndice!];

  List<Object?> get linhaCabecalho {
    final aba = abaSelecionada;
    if (aba == null || indiceCabecalho >= aba.linhas.length) return const [];
    return aba.linhas[indiceCabecalho];
  }

  ImportSummary get resumo => ImportSummary.fromRows(linhas);

  List<ImportRow> get linhasFiltradas => aplicarFiltroRevisao(linhas, filtroRevisao);

  PatrimonioImportState copyWith({
    ImportStep? step,
    String? nomeArquivo,
    List<ImportParsedSheet>? abas,
    int? Function()? abaSelecionadaIndice,
    int? indiceCabecalho,
    String? Function()? delimitadorCsv,
    ImportColumnMapping? mapeamento,
    ImportDefaults? padroes,
    List<ImportRow>? linhas,
    bool? carregando,
    String? Function()? mensagemErro,
    int? progressoAtual,
    int? progressoTotal,
    bool? cancelamentoSolicitado,
    ImportFiltroRevisao? filtroRevisao,
    bool bumpRevisao = false,
    ImportProfileId? Function()? perfilDetectado,
    ImportProfileId? perfilAtivo,
    Map<String, String>? mapeamentoLocalizacoes,
    Set<String>? localizacoesSemMapeamento,
    Map<int, String>? mapeamentoTiposPendentes,
    Set<int>? numerosLinhaTipoPendenteOriginal,
    bool? revalidando,
    int? Function()? revalidacaoConcluidaNaRevisao,
    List<String>? revalidacaoNumerosQueViraramExistentes,
  }) {
    return PatrimonioImportState(
      step: step ?? this.step,
      nomeArquivo: nomeArquivo ?? this.nomeArquivo,
      abas: abas ?? this.abas,
      abaSelecionadaIndice:
          abaSelecionadaIndice != null ? abaSelecionadaIndice() : this.abaSelecionadaIndice,
      indiceCabecalho: indiceCabecalho ?? this.indiceCabecalho,
      delimitadorCsv: delimitadorCsv != null ? delimitadorCsv() : this.delimitadorCsv,
      mapeamento: mapeamento ?? this.mapeamento,
      padroes: padroes ?? this.padroes,
      linhas: linhas ?? this.linhas,
      carregando: carregando ?? this.carregando,
      mensagemErro: mensagemErro != null ? mensagemErro() : this.mensagemErro,
      progressoAtual: progressoAtual ?? this.progressoAtual,
      progressoTotal: progressoTotal ?? this.progressoTotal,
      cancelamentoSolicitado: cancelamentoSolicitado ?? this.cancelamentoSolicitado,
      filtroRevisao: filtroRevisao ?? this.filtroRevisao,
      revisao: bumpRevisao ? revisao + 1 : revisao,
      perfilDetectado: perfilDetectado != null ? perfilDetectado() : this.perfilDetectado,
      perfilAtivo: perfilAtivo ?? this.perfilAtivo,
      mapeamentoLocalizacoes: mapeamentoLocalizacoes ?? this.mapeamentoLocalizacoes,
      localizacoesSemMapeamento: localizacoesSemMapeamento ?? this.localizacoesSemMapeamento,
      mapeamentoTiposPendentes: mapeamentoTiposPendentes ?? this.mapeamentoTiposPendentes,
      numerosLinhaTipoPendenteOriginal:
          numerosLinhaTipoPendenteOriginal ?? this.numerosLinhaTipoPendenteOriginal,
      revalidando: revalidando ?? this.revalidando,
      revalidacaoConcluidaNaRevisao: revalidacaoConcluidaNaRevisao != null
          ? revalidacaoConcluidaNaRevisao()
          : this.revalidacaoConcluidaNaRevisao,
      revalidacaoNumerosQueViraramExistentes:
          revalidacaoNumerosQueViraramExistentes ?? this.revalidacaoNumerosQueViraramExistentes,
    );
  }
}
