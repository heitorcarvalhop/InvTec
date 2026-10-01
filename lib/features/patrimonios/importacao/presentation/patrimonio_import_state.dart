import '../data/spreadsheet_parser.dart';
import '../domain/import_column_mapping.dart';
import '../domain/import_defaults.dart';
import '../domain/import_row.dart';
import '../domain/import_summary.dart';
import '../domain/patrimonio_comparacao.dart';
import '../domain/patrimonio_decisao.dart';
import '../domain/profiles/import_profile_id.dart';

/// Passos do assistente de importação (seção 3) — sempre nesta ordem;
/// nunca importa automaticamente ao selecionar o arquivo. [resolverLocalizacoes]
/// só é visitado quando um perfil com localizações a resolver (hoje, só o
/// GETEC) está ativo — ver [PatrimonioImportState.perfilAtivo].
///
/// PROMPT 11.6.3 — [compararRevisao]/[compararResumo] são o modo ADMIN
/// "Comparar e Atualizar": alcançados a partir do MESMO passo
/// [configurarPadroes]/[resolverLocalizacoes] do assistente convencional
/// (ver [PatrimonioImportState.modoComparacaoAdmin]), nunca um segundo
/// assistente — só o desfecho de "Continuar"/"Analisar planilha" diverge.
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
  compararRevisao,
  compararResumo,
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

/// PROMPT 11.6.3, seção 3 — filtros da lista de revisão do modo ADMIN
/// "Comparar e Atualizar". Opera sobre [ComparacaoLote.itensParaRevisao]
/// (idênticos JÁ excluídos por aquele getter — nunca reaparecem aqui,
/// mesmo com o filtro "Todos").
enum ComparacaoFiltroRevisao {
  todos,
  localizacaoOuSetor,
  outrosMetadados,
  novos,
  bloqueados,
  pendentesDeDecisao,
  selecionadosParaAtualizacao,
  ignorados,
}

extension ComparacaoFiltroRevisaoLabel on ComparacaoFiltroRevisao {
  String get label {
    switch (this) {
      case ComparacaoFiltroRevisao.todos:
        return 'Todos';
      case ComparacaoFiltroRevisao.localizacaoOuSetor:
        return 'Localização/Setor';
      case ComparacaoFiltroRevisao.outrosMetadados:
        return 'Outros metadados';
      case ComparacaoFiltroRevisao.novos:
        return 'Novos';
      case ComparacaoFiltroRevisao.bloqueados:
        return 'Bloqueados';
      case ComparacaoFiltroRevisao.pendentesDeDecisao:
        return 'Pendentes de decisão';
      case ComparacaoFiltroRevisao.selecionadosParaAtualizacao:
        return 'Selecionados para atualização';
      case ComparacaoFiltroRevisao.ignorados:
        return 'Ignorados';
    }
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
    this.comparacao,
    this.modoComparacaoAdmin = false,
    this.decisoes = const {},
    this.filtroComparacao = ComparacaoFiltroRevisao.todos,
    this.buscaNumeroPatrimonio = '',
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

  /// PROMPT 11.6.2 — resultado do modo ADMIN "Comparar e Atualizar",
  /// calculado a partir das MESMAS [linhas] já produzidas pelo assistente
  /// convencional (ver [PatrimonioImportController.compararParaAdmin]).
  /// `null` sempre que esse modo nunca foi acionado nesta sessão — a
  /// importação convencional nunca o preenche, então seu comportamento
  /// (inclusive todo [resumo]/[linhasFiltradas] abaixo) permanece IDÊNTICO
  /// ao de antes deste prompt.
  final ComparacaoLote? comparacao;

  /// PROMPT 11.6.3 — `true` quando o usuário (sempre ADMIN — ver seção 1;
  /// [PatrimonioImportController.definirModoComparacaoAdmin] recusa fora
  /// desse perfil) escolheu "Comparar e Atualizar" em vez da importação
  /// convencional, no passo "Configurar padrões". Decide qual método o
  /// botão "Continuar"/"Analisar planilha" chama
  /// ([PatrimonioImportController.analisar] ou
  /// [PatrimonioImportController.compararParaAdmin]) — nunca cria um
  /// segundo assistente: até aqui, os dois modos compartilham exatamente
  /// os mesmos passos (arquivo, aba, cabeçalho, colunas, padrões,
  /// localizações do perfil GETEC).
  final bool modoComparacaoAdmin;

  /// PROMPT 11.6.3, seção 5 — decisão do ADMIN por campo divergente,
  /// chaveada por [ChaveDecisaoCampo] (patrimonioId + campo — NUNCA um
  /// índice de lista, que muda com filtro/ordenação). Só contém entradas
  /// para patrimônios [ClassificacaoComparacao.divergente]: nunca para
  /// novos (sem cadastro automático — seção 6) nem bloqueados (seção 7).
  /// Reiniciada a CADA nova planilha ([PatrimonioImportController.carregarArquivo]
  /// já reseta o estado inteiro) e a cada nova chamada de
  /// [PatrimonioImportController.compararParaAdmin] (seção 9: "invalidar
  /// as decisões anteriores"). Puramente em memória — nada aqui é
  /// persistido nem enviado a lugar nenhum nesta etapa (seção 10).
  final Map<ChaveDecisaoCampo, DecisaoCampoValor> decisoes;

  /// PROMPT 11.6.3, seção 3 — filtro ativo da lista de revisão do modo
  /// ADMIN.
  final ComparacaoFiltroRevisao filtroComparacao;

  /// PROMPT 11.6.3, seção 3 — texto de busca por número patrimonial na
  /// lista de revisão do modo ADMIN (contains, sem diferenciar caixa).
  final String buscaNumeroPatrimonio;

  /// Decisão atual de um campo — [DecisaoCampoValor.pendente] quando ainda
  /// não há entrada em [decisoes] (nunca lança, nunca exige inicialização
  /// prévia por patrimônio).
  DecisaoCampoValor decisaoDe(String patrimonioId, String campo) =>
      decisoes[ChaveDecisaoCampo(patrimonioId: patrimonioId, campo: campo)] ?? DecisaoCampoValor.pendente;

  /// `true` quando TODAS as divergências de [item] já têm uma decisão
  /// [DecisaoCampoValor.ignorar] — usado pelo filtro "Ignorados" (seção 3) e
  /// pelo resumo de decisões (seção 8: "patrimônios ignorados" nunca conta
  /// quem ainda tem alguma decisão pendente, nem quem tem alguma aplicada).
  bool _totalmenteIgnorado(PatrimonioComparacao item) {
    if (item.divergencias.isEmpty) return false;
    final id = item.patrimonioId;
    if (id == null) return false;
    return item.divergencias.every((d) => decisaoDe(id, d.campo) == DecisaoCampoValor.ignorar);
  }

  bool _temAoMenosUmaAplicacao(PatrimonioComparacao item) {
    final id = item.patrimonioId;
    if (id == null) return false;
    return item.divergencias.any((d) => decisaoDe(id, d.campo) == DecisaoCampoValor.aplicar);
  }

  bool _temAoMenosUmaPendente(PatrimonioComparacao item) {
    final id = item.patrimonioId;
    if (id == null) return false;
    return item.divergencias.any((d) => decisaoDe(id, d.campo) == DecisaoCampoValor.pendente);
  }

  /// PROMPT 11.6.3, seção 8 — etapa de conferência ("resumo das decisões").
  /// Calculado a partir de [comparacao] + [decisoes], nunca armazenado à
  /// parte (uma única fonte de verdade — impossível ficar dessincronizado).
  ComparacaoDecisoesResumo get resumoDecisoes {
    final lote = comparacao;
    if (lote == null) return ComparacaoDecisoesResumo.vazio();

    final divergentes = lote.itens
        .where((i) => i.classificacao == ClassificacaoComparacao.divergente && i.patrimonioId != null)
        .toList();

    var patrimoniosComAlteracao = 0;
    var patrimoniosIgnorados = 0;
    var camposAAtualizar = 0;
    var alteracoesLocalizacaoOuSetor = 0;
    var alteracoesMetadados = 0;
    var decisoesPendentes = 0;

    for (final item in divergentes) {
      final id = item.patrimonioId!;
      if (_temAoMenosUmaAplicacao(item)) patrimoniosComAlteracao++;
      // "Ignorados" (seção 8) nunca conta quem tem alguma aplicação — as
      // duas categorias são mutuamente exclusivas por construção.
      if (!_temAoMenosUmaAplicacao(item) && _totalmenteIgnorado(item)) patrimoniosIgnorados++;

      for (final campo in item.divergencias) {
        switch (decisaoDe(id, campo.campo)) {
          case DecisaoCampoValor.aplicar:
            camposAAtualizar++;
            if (campo.tipo == TipoDivergencia.setor || campo.tipo == TipoDivergencia.localizacao) {
              alteracoesLocalizacaoOuSetor++;
            } else {
              alteracoesMetadados++;
            }
          case DecisaoCampoValor.pendente:
            decisoesPendentes++;
          case DecisaoCampoValor.ignorar:
            break;
        }
      }
    }

    return ComparacaoDecisoesResumo(
      patrimoniosComAlteracaoSelecionada: patrimoniosComAlteracao,
      camposAAtualizar: camposAAtualizar,
      alteracoesLocalizacaoOuSetor: alteracoesLocalizacaoOuSetor,
      alteracoesMetadados: alteracoesMetadados,
      patrimoniosIgnorados: patrimoniosIgnorados,
      itensBloqueados: lote.resumo.bloqueados,
      decisoesPendentes: decisoesPendentes,
    );
  }

  /// PROMPT 11.6.3, seção 3 — [ComparacaoLote.itensParaRevisao] (idênticos
  /// JÁ excluídos), com [filtroComparacao] e [buscaNumeroPatrimonio]
  /// aplicados. `[]` (nunca `null`) quando [comparacao] ainda não existe —
  /// a UI trata isso como "nenhum item", nunca como erro.
  List<PatrimonioComparacao> get itensComparacaoFiltrados {
    final lote = comparacao;
    if (lote == null) return const [];

    var itens = lote.itensParaRevisao;

    final termo = buscaNumeroPatrimonio.trim().toLowerCase();
    if (termo.isNotEmpty) {
      itens = itens.where((i) => (i.numeroPatrimonio ?? '').toLowerCase().contains(termo)).toList();
    }

    switch (filtroComparacao) {
      case ComparacaoFiltroRevisao.todos:
        return itens;
      case ComparacaoFiltroRevisao.localizacaoOuSetor:
        return itens
            .where(
              (i) => i.divergencias.any(
                (d) => d.tipo == TipoDivergencia.setor || d.tipo == TipoDivergencia.localizacao,
              ),
            )
            .toList();
      case ComparacaoFiltroRevisao.outrosMetadados:
        return itens.where((i) => i.divergencias.any((d) => d.tipo == TipoDivergencia.metadado)).toList();
      case ComparacaoFiltroRevisao.novos:
        return itens.where((i) => i.classificacao == ClassificacaoComparacao.novo).toList();
      case ComparacaoFiltroRevisao.bloqueados:
        return itens.where((i) => i.classificacao == ClassificacaoComparacao.bloqueado).toList();
      case ComparacaoFiltroRevisao.pendentesDeDecisao:
        return itens
            .where((i) => i.classificacao == ClassificacaoComparacao.divergente && _temAoMenosUmaPendente(i))
            .toList();
      case ComparacaoFiltroRevisao.selecionadosParaAtualizacao:
        return itens
            .where((i) => i.classificacao == ClassificacaoComparacao.divergente && _temAoMenosUmaAplicacao(i))
            .toList();
      case ComparacaoFiltroRevisao.ignorados:
        return itens
            .where((i) => i.classificacao == ClassificacaoComparacao.divergente && _totalmenteIgnorado(i))
            .toList();
    }
  }

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
    ComparacaoLote? Function()? comparacao,
    bool? modoComparacaoAdmin,
    Map<ChaveDecisaoCampo, DecisaoCampoValor>? decisoes,
    ComparacaoFiltroRevisao? filtroComparacao,
    String? buscaNumeroPatrimonio,
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
      comparacao: comparacao != null ? comparacao() : this.comparacao,
      modoComparacaoAdmin: modoComparacaoAdmin ?? this.modoComparacaoAdmin,
      decisoes: decisoes ?? this.decisoes,
      filtroComparacao: filtroComparacao ?? this.filtroComparacao,
      buscaNumeroPatrimonio: buscaNumeroPatrimonio ?? this.buscaNumeroPatrimonio,
    );
  }
}

/// PROMPT 11.6.3, seção 8 — contagens da etapa "Resumo das decisões".
/// [patrimoniosComAlteracaoSelecionada] e [patrimoniosIgnorados] nunca se
/// sobrepõem (cada patrimônio divergente cai em NO MÁXIMO uma das duas —
/// ver [PatrimonioImportState.resumoDecisoes]) e nenhum patrimônio é
/// contado mais de uma vez dentro da mesma categoria.
class ComparacaoDecisoesResumo {
  const ComparacaoDecisoesResumo({
    required this.patrimoniosComAlteracaoSelecionada,
    required this.camposAAtualizar,
    required this.alteracoesLocalizacaoOuSetor,
    required this.alteracoesMetadados,
    required this.patrimoniosIgnorados,
    required this.itensBloqueados,
    required this.decisoesPendentes,
  });

  factory ComparacaoDecisoesResumo.vazio() => const ComparacaoDecisoesResumo(
    patrimoniosComAlteracaoSelecionada: 0,
    camposAAtualizar: 0,
    alteracoesLocalizacaoOuSetor: 0,
    alteracoesMetadados: 0,
    patrimoniosIgnorados: 0,
    itensBloqueados: 0,
    decisoesPendentes: 0,
  );

  final int patrimoniosComAlteracaoSelecionada;
  final int camposAAtualizar;
  final int alteracoesLocalizacaoOuSetor;
  final int alteracoesMetadados;
  final int patrimoniosIgnorados;
  final int itensBloqueados;
  final int decisoesPendentes;
}
