import '../../domain/patrimonio_detalhe.dart';
import 'import_column_field.dart';
import 'import_row.dart';

/// PROMPT 11.6.2 — classificação de UM patrimônio (uma linha já
/// correspondida por número patrimonial) no modo ADMIN "Comparar e
/// Atualizar". Deliberadamente SEPARADA de [ImportRowStatus]: aquele enum
/// continua sendo a ÚNICA fonte de verdade da importação CONVENCIONAL
/// (cadastro de novos + atualização de metadados por decisão individual) —
/// nada neste arquivo altera [ImportAnalyzer.classificar] nem qualquer
/// transição/regra já homologada. Este é um SEGUNDO OLHAR, só de LEITURA,
/// sobre as mesmas [ImportRow] já produzidas por [ImportAnalyzer.analisar].
enum ClassificacaoComparacao {
  /// Todos os campos comparáveis efetivamente fornecidos pela planilha
  /// batem com o cadastro atual do InvTec — seção 1/5: retirado da futura
  /// lista de decisões, mas contado no resumo.
  identico,

  /// Pelo menos um campo comparável diverge do cadastro atual.
  divergente,

  /// Número patrimonial da planilha não existe no InvTec.
  novo,

  /// Não é seguro classificar esta linha em nenhuma das três categorias
  /// acima sem uma decisão manual — nunca escolhida por aproximação (ver
  /// [PatrimonioComparacao.motivoBloqueio]).
  bloqueado,
}

/// A que tipo de dado uma [CampoDivergente] pertence — só para agrupar a
/// contagem por campo no resumo (seção 5); nenhum dos três é "mais grave"
/// que o outro aqui (gravidade é [CampoDivergente.exigeResolucao]).
enum TipoDivergencia { metadado, setor, localizacao }

/// Uma divergência de UM campo, dentro de UM patrimônio (seção 4). Vários
/// [CampoDivergente] podem pertencer ao mesmo [PatrimonioComparacao] — o
/// patrimônio é contado UMA vez no resumo (`divergentes`), mesmo com várias
/// divergências; é [ComparacaoResumo.divergenciasPorCampo] quem conta por
/// campo.
class CampoDivergente {
  const CampoDivergente({
    required this.campo,
    required this.tipo,
    required this.valorInvtec,
    required this.valorPlanilha,
    this.exigeResolucao = false,
    this.valorPlanilhaId,
  });

  /// Rótulo pronto para exibição (ex.: "Descrição", "Setor atual").
  final String campo;
  final TipoDivergencia tipo;
  final String? valorInvtec;
  final String? valorPlanilha;

  /// `true` quando a planilha trouxe um texto de setor/localização que não
  /// pôde ser resolvido com segurança contra um cadastro real do InvTec
  /// (seção 3: "se uma localização da planilha não puder ser identificada
  /// com segurança, classificá-la como pendente de resolução, sem escolher
  /// um destino por aproximação") — a linha inteira fica
  /// [ClassificacaoComparacao.bloqueado] quando isto ocorre.
  final bool exigeResolucao;

  /// PROMPT 11.6.4 — só preenchido quando [tipo] é [TipoDivergencia.setor]
  /// ou [TipoDivergencia.localizacao]: o id JÁ RESOLVIDO (contra o catálogo
  /// real do InvTec) que a execução segura precisa enviar a
  /// `registrar_movimentacao` — nunca o texto de [valorPlanilha], que é só
  /// para exibição. `null` em qualquer divergência de metadado (esses são
  /// aplicados por texto simples, sem catálogo envolvido).
  final String? valorPlanilhaId;
}

/// Resultado da comparação de UM patrimônio (uma linha da planilha já
/// correspondida, ou não, a um cadastro existente).
class PatrimonioComparacao {
  const PatrimonioComparacao({
    required this.numeroLinha,
    required this.numeroPatrimonio,
    required this.classificacao,
    this.patrimonioId,
    this.divergencias = const [],
    this.motivoBloqueio,
    this.versaoAtualizadoEm,
  });

  /// Número da linha na planilha original (1-based) — mesmo campo de
  /// [ImportRow.numeroLinha], para o usuário localizar a linha no arquivo.
  final int numeroLinha;

  /// Número patrimonial como veio da planilha (pode ser `null` quando a
  /// própria linha é o motivo do bloqueio — ver [motivoBloqueio]).
  final String? numeroPatrimonio;

  final ClassificacaoComparacao classificacao;

  /// `null` quando [classificacao] é [ClassificacaoComparacao.novo] (ainda
  /// não existe no InvTec) ou [ClassificacaoComparacao.bloqueado].
  final String? patrimonioId;

  /// Vazio a menos que [classificacao] seja
  /// [ClassificacaoComparacao.divergente].
  final List<CampoDivergente> divergencias;

  /// Preenchido só quando [classificacao] é
  /// [ClassificacaoComparacao.bloqueado] — explica exatamente por quê,
  /// nunca um bloqueio silencioso.
  final String? motivoBloqueio;

  /// PROMPT 11.6.4 — `patrimonios.atualizado_em` no momento em que ESTA
  /// comparação rodou (só preenchido quando [patrimonioId] não é nulo). É a
  /// referência de concorrência otimista que a execução segura envia como
  /// `p_versao_esperada`: se o patrimônio mudou no banco depois deste
  /// instante, a RPC recusa a escrita como um conflito, nunca sobrescreve
  /// silenciosamente (seção 5 do PROMPT 11.6.4).
  final DateTime? versaoAtualizadoEm;
}

/// Contagens agregadas (seção 5) — "consistentes e não duplicadas": cada
/// linha analisada contribui para EXATAMENTE uma das quatro categorias
/// principais, e [totalLinhas] é sempre a soma delas.
class ComparacaoResumo {
  const ComparacaoResumo({
    required this.totalLinhas,
    required this.identicos,
    required this.divergentes,
    required this.novos,
    required this.bloqueados,
    required this.divergenciasPorCampo,
  });

  factory ComparacaoResumo.vazio() => const ComparacaoResumo(
    totalLinhas: 0,
    identicos: 0,
    divergentes: 0,
    novos: 0,
    bloqueados: 0,
    divergenciasPorCampo: {},
  );

  final int totalLinhas;
  final int identicos;
  final int divergentes;
  final int novos;
  final int bloqueados;

  /// Rótulo do campo (ex.: "Localização atual") → quantas vezes ele
  /// divergiu no lote inteiro — um patrimônio com 2 divergências soma 1 em
  /// CADA um dos 2 campos aqui, mas só 1 em [divergentes] (seção 4: "sem
  /// contar o patrimônio várias vezes no total geral").
  final Map<String, int> divergenciasPorCampo;
}

/// Resultado completo de uma comparação (uma planilha inteira).
class ComparacaoLote {
  const ComparacaoLote({required this.itens, required this.resumo});

  /// TODOS os itens analisados, IDÊNTICOS incluídos (seção 5: "não
  /// descartar essas informações da análise; apenas retirá-las da FUTURA
  /// lista de decisões") — ver [itensParaRevisao].
  final List<PatrimonioComparacao> itens;
  final ComparacaoResumo resumo;

  /// Lista pronta para uma futura tela de decisões (PROMPT 11.6.3):
  /// idênticos automaticamente retirados daqui — a contagem deles continua
  /// em [resumo.identicos], nunca perdida.
  List<PatrimonioComparacao> get itensParaRevisao =>
      itens.where((item) => item.classificacao != ClassificacaoComparacao.identico).toList();
}

/// Motor de comparação — PURO (nenhuma chamada de rede, nenhuma escrita),
/// testável com fakes. Opera inteiramente sobre [ImportRow]s JÁ produzidas
/// por [ImportAnalyzer.analisar] (mesma leitura de planilha, mesmo
/// mapeamento de colunas, mesma normalização de número patrimonial, mesma
/// consulta em lote a `buscarPorNumerosPatrimonio`, mesmos catálogos de
/// tipo/setor/localização — PROMPT 11.6.2, seção 2: "reaproveitar ao
/// máximo") — nenhuma leitura de planilha nem resolução de campo é
/// duplicada aqui.
class PatrimonioComparador {
  const PatrimonioComparador._();

  static ComparacaoLote comparar(List<ImportRow> linhas) {
    final itens = <PatrimonioComparacao>[];
    final divergenciasPorCampo = <String, int>{};
    var identicos = 0;
    var divergentes = 0;
    var novos = 0;
    var bloqueados = 0;

    for (final linha in linhas) {
      final item = _compararLinha(linha);
      itens.add(item);
      switch (item.classificacao) {
        case ClassificacaoComparacao.identico:
          identicos++;
        case ClassificacaoComparacao.divergente:
          divergentes++;
          for (final divergencia in item.divergencias) {
            divergenciasPorCampo.update(divergencia.campo, (v) => v + 1, ifAbsent: () => 1);
          }
        case ClassificacaoComparacao.novo:
          novos++;
        case ClassificacaoComparacao.bloqueado:
          bloqueados++;
      }
    }

    return ComparacaoLote(
      itens: itens,
      resumo: ComparacaoResumo(
        totalLinhas: linhas.length,
        identicos: identicos,
        divergentes: divergentes,
        novos: novos,
        bloqueados: bloqueados,
        divergenciasPorCampo: Map.unmodifiable(divergenciasPorCampo),
      ),
    );
  }

  static PatrimonioComparacao _compararLinha(ImportRow linha) {
    // Número patrimonial ausente/ilegível nesta linha — nunca comparável a
    // nada (nem "novo", que exige um número para virar chave de cadastro).
    if (linha.numeroPatrimonioNormalizado == null) {
      return PatrimonioComparacao(
        numeroLinha: linha.numeroLinha,
        numeroPatrimonio: linha.numeroPatrimonio,
        classificacao: ClassificacaoComparacao.bloqueado,
        motivoBloqueio: 'Número patrimonial ausente ou não reconhecido nesta linha.',
      );
    }

    // Mesma checagem de duplicidade DENTRO do arquivo que a importação
    // convencional já faz (`ImportAnalyzer._marcarDuplicadosNoArquivo`,
    // reaproveitada via [ImportRow.duplicadoNoArquivo] — nunca recalculada
    // aqui).
    if (linha.duplicadoNoArquivo) {
      return PatrimonioComparacao(
        numeroLinha: linha.numeroLinha,
        numeroPatrimonio: linha.numeroPatrimonio,
        classificacao: ClassificacaoComparacao.bloqueado,
        motivoBloqueio: 'Número patrimonial duplicado dentro da própria planilha.',
      );
    }

    // Localização: reaproveita INTEIRAMENTE a resolução já feita pelo
    // perfil ativo (GETEC ou outro) antes desta comparação rodar — nunca
    // resolvida de novo aqui. `localizacaoPendente`/`localizacaoOficialAusente`
    // já significam, na origem, "texto que não pôde ser identificado com
    // segurança" (seção 3) — nunca uma escolha por aproximação.
    if (linha.localizacaoPendente || linha.localizacaoOficialAusente) {
      return PatrimonioComparacao(
        numeroLinha: linha.numeroLinha,
        numeroPatrimonio: linha.numeroPatrimonio,
        classificacao: ClassificacaoComparacao.bloqueado,
        motivoBloqueio: linha.localizacaoOficialAusente
            ? "Localização '${linha.localizacaoTexto}' é um nome oficial conhecido, mas não está "
                  'cadastrada/ativa no InvTec — verifique se foi renomeada ou desativada.'
            : "Localização '${linha.localizacaoTexto}' não foi identificada com segurança — exige "
                  'resolução manual antes de comparar.',
      );
    }

    // Setor: mesma cautela da localização (seção 3), mas o setor genérico
    // (`ImportColumnField.setor`/`_resolverSetorComPadrao`) tem uma
    // diferença importante — ele pode cair num PADRÃO configurado da
    // importação quando o texto da linha não resolve (ou está ausente).
    // Comparar contra esse padrão seria comparar algo que a PLANILHA nunca
    // disse para esta linha especificamente (seção 3: "não comparar campos
    // ausentes como se fossem alterações") — por isso o gate usa sempre o
    // TEXTO BRUTO da própria linha ([ImportRow.setorTexto]), nunca
    // [ImportRow.destinoIdResolvido] sozinho (que pode vir do padrão).
    final temColunaSetor = linha.celulas.containsKey(ImportColumnField.setor);
    final textoSetor = linha.setorTexto?.trim();
    final setorFoiInformado = temColunaSetor && textoSetor != null && textoSetor.isNotEmpty;
    final setorResolvidoPelaPropriaLinha = linha.destinoIdResolvido != null && !linha.usouDestinoPadrao;
    if (setorFoiInformado && !setorResolvidoPelaPropriaLinha) {
      return PatrimonioComparacao(
        numeroLinha: linha.numeroLinha,
        numeroPatrimonio: linha.numeroPatrimonio,
        classificacao: ClassificacaoComparacao.bloqueado,
        motivoBloqueio: "Setor '${linha.setorTexto}' não foi identificado com segurança — exige "
            'resolução manual antes de comparar.',
      );
    }

    final existente = linha.existenteNoBanco;
    if (existente == null) {
      // Reaproveita `linha.issues`, já calculados por
      // `ImportAnalyzer.classificar` (tipo não encontrado, origem ausente,
      // origem == destino etc.) — nenhuma regra de bloqueio de "novo"
      // duplicada aqui.
      if (linha.temErro) {
        return PatrimonioComparacao(
          numeroLinha: linha.numeroLinha,
          numeroPatrimonio: linha.numeroPatrimonio,
          classificacao: ClassificacaoComparacao.bloqueado,
          motivoBloqueio: linha.issues
              .where((i) => i.severity == ImportIssueSeverity.erro)
              .map((i) => i.message)
              .join(' '),
        );
      }
      return PatrimonioComparacao(
        numeroLinha: linha.numeroLinha,
        numeroPatrimonio: linha.numeroPatrimonio,
        classificacao: ClassificacaoComparacao.novo,
      );
    }

    final patrimonioAtual = existente.patrimonio;
    final divergencias = <CampoDivergente>[
      ..._compararMetadados(linha, existente),
      if (setorFoiInformado &&
          setorResolvidoPelaPropriaLinha &&
          linha.destinoIdResolvido != patrimonioAtual.setorAtualId)
        CampoDivergente(
          campo: 'Setor atual',
          tipo: TipoDivergencia.setor,
          valorInvtec: existente.setorNome,
          valorPlanilha: linha.setorTexto,
          valorPlanilhaId: linha.destinoIdResolvido,
        ),
      if (linha.localizacaoIdResolvida != null &&
          linha.localizacaoIdResolvida != patrimonioAtual.localizacaoAtualId)
        CampoDivergente(
          campo: 'Localização atual',
          tipo: TipoDivergencia.localizacao,
          valorInvtec: existente.localizacaoNome ?? '(sem localização)',
          valorPlanilha: linha.localizacaoTexto,
          valorPlanilhaId: linha.localizacaoIdResolvida,
        ),
    ];

    return PatrimonioComparacao(
      numeroLinha: linha.numeroLinha,
      numeroPatrimonio: linha.numeroPatrimonio,
      patrimonioId: patrimonioAtual.id,
      classificacao: divergencias.isEmpty ? ClassificacaoComparacao.identico : ClassificacaoComparacao.divergente,
      divergencias: divergencias,
      versaoAtualizadoEm: patrimonioAtual.atualizadoEm,
    );
  }

  /// Compara os metadados "de texto simples" — os mesmos que
  /// `PatrimonioRepository.atualizar()` já é capaz de tocar (seção 4:
  /// "outros metadados já suportados pelo importador"). Setor e localização
  /// ficam de fora daqui de propósito: precisam da cautela extra de
  /// resolução contra um catálogo (ver [_compararLinha]), não uma simples
  /// comparação de texto.
  static List<CampoDivergente> _compararMetadados(ImportRow linha, PatrimonioDetalhe existente) {
    final p = existente.patrimonio;
    final divergencias = <CampoDivergente>[];

    void comparar(ImportColumnField campo, String rotulo, String? valorPlanilha, String? valorAtual) {
      // Coluna nem mapeada nesta importação — nada a comparar (seção 3).
      if (!linha.celulas.containsKey(campo)) return;
      final planilha = valorPlanilha?.trim();
      // Célula vazia NESTA linha — nunca interpretado como "a planilha
      // pede para apagar o valor atual" (seção 3).
      if (planilha == null || planilha.isEmpty) return;
      final atual = valorAtual?.trim();
      // Comparação exata (sem normalizações agressivas — seção 3: uma
      // diferença de acentuação/pontuação real continua visível).
      if (planilha == (atual ?? '')) return;
      divergencias.add(
        CampoDivergente(campo: rotulo, tipo: TipoDivergencia.metadado, valorInvtec: valorAtual, valorPlanilha: valorPlanilha),
      );
    }

    // PROMPT 11.6.5, seção 4 — `numero_patrimonio` NUNCA entra como campo
    // comparável/aplicável aqui: é a CHAVE que casa a linha da planilha com
    // este próprio patrimônio (ver `buscarPorNumerosPatrimonio`/
    // `numeroPatrimonioNormalizado`) — comparar/aplicar por este fluxo
    // misturaria identidade do registro com conteúdo do registro. Uma
    // correção de tombamento tem procedimento administrativo separado e
    // explícito (edição normal do patrimônio), nunca por aqui.
    comparar(ImportColumnField.descricao, 'Descrição', linha.descricao, p.descricao);
    comparar(ImportColumnField.marca, 'Marca', linha.marca, p.marca);
    comparar(ImportColumnField.modelo, 'Modelo', linha.modelo, p.modelo);
    comparar(ImportColumnField.numeroSerie, 'Número de série', linha.numeroSerie, p.numeroSerie);
    comparar(ImportColumnField.observacao, 'Observação', linha.observacao, p.observacao);

    return divergencias;
  }
}
