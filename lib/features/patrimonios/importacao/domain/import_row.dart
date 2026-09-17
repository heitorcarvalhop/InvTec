import '../../domain/patrimonio_detalhe.dart';
import 'import_column_field.dart';

enum ImportIssueSeverity { erro, aviso }

class ImportIssue {
  const ImportIssue(this.severity, this.message);

  final ImportIssueSeverity severity;
  final String message;
}

/// Classificação final da linha (seção 20) — exatamente estes 6 valores,
/// sem um status extra para "duplicado dentro do arquivo": duplicidade é um
/// caso particular de ERRO até o usuário decidir qual ocorrência manter
/// (ver [ImportRow.duplicadoNoArquivo]).
enum ImportRowStatus { pronto, aviso, erro, ignorado, existente, atualizar }

extension ImportRowStatusLabel on ImportRowStatus {
  String get label {
    switch (this) {
      case ImportRowStatus.pronto:
        return 'Pronto';
      case ImportRowStatus.aviso:
        return 'Aviso';
      case ImportRowStatus.erro:
        return 'Erro';
      case ImportRowStatus.ignorado:
        return 'Ignorado';
      case ImportRowStatus.existente:
        return 'Já existente';
      case ImportRowStatus.atualizar:
        return 'Atualizar';
    }
  }
}

/// Decisão do usuário para um patrimônio cujo número já existe no InvTec
/// (seção 16) — nunca há opção de criar um duplicado.
enum ImportExistingAction { manterExistente, atualizarMetadados }

/// Resultado da tentativa de gravação de uma linha (seção 28: falha
/// parcial nunca derruba a importação inteira).
class ImportRowResult {
  const ImportRowResult({required this.sucesso, this.mensagemErro, this.patrimonioId});

  final bool sucesso;
  final String? mensagemErro;
  final String? patrimonioId;
}

/// Uma linha de dados da planilha, do texto bruto lido até a classificação
/// final pronta para gravação. É mutável de propósito: milhares de linhas
/// são reclassificadas repetidamente (mapeamento, padrões, decisões
/// individuais) e recriar objetos imutáveis a cada mudança seria caro sem
/// necessidade — ver ImportAnalyzer.
class ImportRow {
  ImportRow({required this.numeroLinha, required this.celulas});

  /// Número da linha na planilha original (1-based) — para o usuário achar
  /// a linha no arquivo original.
  final int numeroLinha;

  /// Texto bruto (já convertido de célula para String) de cada coluna
  /// mapeada, antes de qualquer resolução ou aplicação de padrão.
  final Map<ImportColumnField, String?> celulas;

  // --- campos resolvidos pelo ImportAnalyzer ---
  String? numeroPatrimonio;
  String? numeroPatrimonioNormalizado;
  String? numeroSerie;
  String? marca;
  String? modelo;
  String? descricao;
  String? observacao;
  String? motivo;
  DateTime? dataAquisicao;
  DateTime? dataEntrada;
  String? responsavelDestino;

  String? tipoTexto;
  String? tipoIdResolvido;
  String? tipoIdSugerido;

  String? setorTexto;
  String? destinoIdResolvido;
  String? destinoIdSugerido;

  String? origemTexto;
  String? origemIdResolvido;
  String? origemIdSugerido;

  bool usouDestinoPadrao = false;
  bool usouOrigemPadrao = false;
  bool usouResponsavelPadrao = false;
  bool usouMotivoPadrao = false;
  bool usouDataPadrao = false;

  /// Célula preenchida mas que não foi possível interpretar como data —
  /// usado por [ImportAnalyzer.classificar] para gerar o aviso
  /// correspondente (não é adicionado diretamente às issues durante a
  /// resolução, já que `classificar` limpa `issues` a cada chamada).
  bool dataAquisicaoNaoReconhecida = false;
  bool dataEntradaNaoReconhecida = false;

  /// `true` quando um perfil considera aceitável esta linha ficar sem
  /// origem resolvida (ex.: carga inicial GETEC, cuja planilha não tem
  /// nenhuma coluna de origem histórica) — só suprime o erro genérico de
  /// "origem obrigatória" quando a célula de origem também está vazia
  /// (nunca mascara um texto de origem que existia mas não resolveu).
  bool origemDispensada = false;

  bool duplicadoNoArquivo = false;
  PatrimonioDetalhe? existenteNoBanco;
  ImportExistingAction? acaoExistente;
  bool possivelDuplicidadeSerial = false;
  bool ignoradaManualmente = false;

  /// Sinal genérico interpretado por [ImportAnalyzer.classificar] como
  /// aviso de possível baixa — infraestrutura neutra, disponível para
  /// qualquer perfil futuro que queira usá-la; nenhum perfil ativo hoje a
  /// preenche (o perfil GETEC deixou de fazê-lo no PROMPT 8.12: "BAIXAS
  /// LOCALIZADAS" é uma decisão de negócio conhecida de bem
  /// recuperado/relocalizado, nunca indício de baixa atual).
  bool possivelBaixa = false;

  /// `true` quando o tipo não veio de uma coluna mapeada e sim foi deduzido
  /// automaticamente (ex.: inferência por descrição do perfil GETEC) — usado
  /// só para mostrar a etiqueta "Inferido" na revisão.
  bool tipoInferidoAutomaticamente = false;

  /// `true` quando o tipo foi escolhido explicitamente pelo usuário na tela
  /// de pendências de tipo (PROMPT 8.13, individualmente ou via "Aplicar aos
  /// semelhantes") — decisão local desta sessão de importação, nunca vira
  /// regra do classificador (`tipo_inference.dart` continua intocado).
  bool tipoResolvidoManualmente = false;

  // --- Localização (dentro do setor/gerência de destino) ---
  //
  // Resolvido inteiramente fora do ImportAnalyzer genérico (que não
  // conhece o conceito de Localizacao) — ver GetecImportProfile e
  // PatrimonioImportController._aplicarPosProcessamentoGetec. Os campos
  // abaixo são infraestrutura genérica (qualquer perfil poderia setá-los),
  // só interpretados por `classificar` de forma neutra, igual a
  // `possivelBaixa`/`usouDestinoPadrao`.
  String? localizacaoTexto;
  String? localizacaoIdResolvida;

  /// `true` quando havia texto de localização na planilha mas ele ainda
  /// não foi resolvido nem teve uma decisão explícita do usuário ("importar
  /// sem localização") — gera ERRO e BLOQUEIA o envio (PROMPT 8.9.1: um
  /// texto de localização genuinamente desconhecido nunca pode ser
  /// importado silenciosamente sem decisão). Não é um bloqueio permanente:
  /// assim que o usuário mapear manualmente para uma localização existente
  /// ou confirmar "importar sem localização", a linha é reclassificada e
  /// deixa de estar pendente.
  bool localizacaoPendente = false;

  /// `true` quando o texto de localização é um dos valores que a GETEC usa
  /// para dizer explicitamente "isto não é um local físico" (ex.:
  /// "INTANGÍVEIS", "TI - SOFTWARE", "BAIXAS LOCALIZADAS" — ver
  /// `GetecImportProfile.ehValorSemLocalizacaoConhecido`). Decisão CONHECIDA
  /// do importador, nunca uma pendência: `localizacaoIdResolvida` continua
  /// `null` de propósito, sem gerar aviso nem erro.
  bool localizacaoSemLocalizacaoPorRegra = false;

  /// `true` quando o texto de localização bate com um dos nomes OFICIAIS
  /// conhecidos da GETEC (ver `GetecImportProfile.nomeOficialConhecido`),
  /// mas essa localização não está entre as localizações ATIVAS carregadas
  /// do Supabase para a gerência — nunca vira `null` silenciosamente: gera
  /// um ERRO explícito (provável indício de localização renomeada ou
  /// desativada no banco desde que este mapeamento foi definido).
  bool localizacaoOficialAusente = false;

  final List<ImportIssue> issues = [];
  ImportRowStatus status = ImportRowStatus.pronto;
  ImportRowResult? resultado;

  bool get temErro => issues.any((i) => i.severity == ImportIssueSeverity.erro);
  bool get temAviso => issues.any((i) => i.severity == ImportIssueSeverity.aviso);

  /// Vai para o Supabase nesta importação (novo cadastro ou atualização de
  /// metadados) — usado para contar "prontos para importar" e para o loop
  /// de gravação.
  bool get seraEnviada =>
      status == ImportRowStatus.pronto ||
      status == ImportRowStatus.aviso ||
      status == ImportRowStatus.atualizar;
}
