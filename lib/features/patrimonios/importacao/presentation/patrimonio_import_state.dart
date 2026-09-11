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
        return 'Prontos';
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

  /// Localização da planilha (texto normalizado) → nome do setor escolhido
  /// pelo usuário no passo de localizações (seção 15/16) — vazio significa
  /// "usar destino padrão ou deixar pendente", nunca criação automática de
  /// setor (seção 16).
  final Map<String, String> mapeamentoLocalizacoes;

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
    );
  }
}
