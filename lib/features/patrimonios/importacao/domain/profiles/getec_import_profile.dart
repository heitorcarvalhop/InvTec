import '../../../../localizacoes/domain/localizacao.dart';
import '../../../../setores/domain/setor.dart';
import '../import_column_field.dart';
import '../import_column_mapping.dart';
import '../text_similarity.dart';
import 'unit_import_profile.dart';

/// Regras específicas da planilha real usada pela GETEC ("aba
/// RelatorioBemPermanente") — nada aqui é usado a menos que o perfil seja
/// explicitamente detectado E ativado pelo usuário; o importador genérico
/// (`ImportAnalyzer`, `ImportColumnField`) nunca importa nada deste arquivo
/// e continua funcionando de forma idêntica sem ele.
///
/// Fachada concreta sobre [UnitImportProfile] (estrutura genérica,
/// orientada a dados, pronta para outras unidades): toda a lógica de
/// detecção/mapeamento/resolução de localização mora em [perfil]; esta
/// classe só expõe os mesmos métodos estáticos de sempre, delegando a ele,
/// mais as regras de negócio exclusivas da GETEC (tombamento anterior,
/// "BAIXAS LOCALIZADAS") que não fazem parte da estrutura genérica.
class GetecImportProfile {
  const GetecImportProfile._();

  /// Campos em que "10" é um marcador legado de "não informado" — só se
  /// aplica quando este perfil está ativo, nunca globalmente.
  static const camposComSentinela10 = {ImportColumnField.numeroSerie, ImportColumnField.tombamentoAnterior};

  /// Os 15 nomes OFICIAIS de localização física cadastrados no InvTec para
  /// a gerência GETEC, tal como devem existir em `Localizacao.nome`.
  static const _nomesLocalizacoesOficiais = [
    'GETEC - UNIVERSITÁRIO',
    'SEDE - PARQUE AMAZÔNIA - PISO I',
    'HOME OFFICE',
    'PARQUE AMAZÔNIA - RACK PISO II',
    'GETEC-PPLT',
    'DATACENTER - UNIVERSITÁRIO',
    'PARQUE AMAZÔNIA - RACK GABINETE',
    'SITUAÇÃO/SITUADA - PA',
    'SEDE - PARQUE AMAZÔNIA PISO II',
    'GETEC - LOBO GUARA',
    'GETEC - CORUJA SUINDARA',
    'GETEC - ONÇA PINTADA',
    'SALA DOS INSERVÍVEIS',
    'GETEC - CANIDÉ',
    'SEMAD - UNIVERSITÁRIO',
  ];

  /// Instância concreta da estrutura genérica [UnitImportProfile] com todas
  /// as regras da GETEC — sigla, cabeçalhos reais, localizações oficiais,
  /// apelido conhecido e valores sem localização. `static final` (não
  /// `const`): [UnitImportProfile] pré-computa mapas normalizados no
  /// construtor.
  static final UnitImportProfile perfil = UnitImportProfile(
    sigla: 'GETEC',
    nomeCompleto: 'GERÊNCIA DE TECNOLOGIA',
    // Cabeçalhos reais da planilha, já como texto normalizado (sem
    // acento/maiúsculas/pontuação) → campo do InvTec correspondente. A
    // coluna "localizacao" da planilha é a Localização dentro da gerência
    // GETEC — NUNCA o setor/gerência em si: a gerência da carga inteira é
    // fixa (destino padrão da importação), nunca derivada desta coluna.
    cabecalhosAlvo: const {
      ImportColumnField.numeroPatrimonio: 'tombamento',
      ImportColumnField.tombamentoAnterior: 'tomb anterior',
      ImportColumnField.descricao: 'descricao',
      ImportColumnField.localizacao: 'localizacao',
      ImportColumnField.marca: 'marca',
      ImportColumnField.numeroSerie: 'n serie',
    },
    // Exige as duas colunas mais distintivas (tombamento + descrição) e ao
    // menos 4 das 6 colunas conhecidas — suficiente para não disparar em
    // falso numa planilha genérica que só por acaso tenha uma coluna
    // "Descrição" ou "Marca".
    cabecalhosObrigatoriosDeteccao: const {'tombamento', 'descricao'},
    minimoCamposReconhecidosDeteccao: 4,
    camposComSentinelaAusencia: camposComSentinela10,
    ehSentinelaAusencia: (valor) =>
        (valor is num && valor == 10) || (valor is String && valor.trim() == '10'),
    nomesLocalizacoesOficiais: _nomesLocalizacoesOficiais,
    // Forma antiga/alternativa usada na planilha para um nome oficial já
    // listado acima — hoje só "SITUAÇÃO - PA" (planilha) → "SITUAÇÃO/
    // SITUADA - PA" (nome oficial cadastrado; PA = Parque Amazônia).
    apelidosLocalizacao: const {'SITUAÇÃO - PA': 'SITUAÇÃO/SITUADA - PA'},
    // Valores da coluna "localizacao" que a GETEC usa para dizer
    // explicitamente que aquele registro NÃO tem localização física
    // associada — nunca tratados como pendência nem erro.
    valoresSemLocalizacaoConhecidos: const ['INTANGÍVEIS', 'TI - SOFTWARE', 'BAIXAS LOCALIZADAS'],
    motivoPadraoSugerido:
        'Carga inicial do inventário patrimonial da GETEC - origem histórica não informada.',
    mensagemDeteccao: 'Formato de inventário GETEC reconhecido.',
  );

  static String get mensagemDeteccao => perfil.mensagemDeteccao;

  /// Sugestão de UX — nunca aplicada por cima de um motivo que o usuário
  /// já tenha digitado.
  static String get motivoPadraoSugerido => perfil.motivoPadraoSugerido;

  /// Sigla usada para identificar a gerência GETEC entre os setores ativos
  /// carregados do Supabase — a GETEC sempre tem sigla oficial cadastrada.
  static String get siglaGerencia => perfil.sigla!;

  /// Encontra a gerência GETEC entre [setoresAtivos] — por SIGLA, nunca por
  /// UUID hardcoded. `null` quando não há exatamente UMA gerência com essa
  /// sigla entre os setores ativos: para este perfil, todo bem da carga
  /// pertence à GETEC, então uma ausência ou ambiguidade é bloqueante, nunca
  /// resolvida silenciosamente.
  static Setor? encontrarGerenciaGetec(List<Setor> setoresAtivos) => perfil.encontrarGerencia(setoresAtivos);

  /// Reconhece o formato pelo CONJUNTO de cabeçalhos, nunca pelo nome da
  /// aba.
  static bool detectar(List<Object?> cabecalho) => perfil.detectar(cabecalho);

  /// Mapeamento automático sugerido — ainda passa pela etapa de revisão do
  /// usuário como qualquer outra sugestão de mapeamento.
  static ImportColumnMapping mapeamentoSugerido(List<Object?> cabecalho) => perfil.mapeamentoSugerido(cabecalho);

  /// Valor textual/numericamente equivalente a "10" vira ausência de
  /// informação nos campos [camposComSentinela10].
  static Object? limparSentinela10(Object? valor) => perfil.limparSentinela(valor);

  // ---------------------------------------------------------------------
  // Mapeamento oficial de localizações
  // ---------------------------------------------------------------------

  /// `true` quando [texto] é um dos valores conhecidos que explicitamente
  /// NÃO representam uma localização física — usado para decidir
  /// `localizacaoDestinoId = null` sem gerar pendência nem erro.
  static bool ehValorSemLocalizacaoConhecido(String texto) => perfil.ehValorSemLocalizacaoConhecido(texto);

  static final String _baixasLocalizadasNormalizado = normalizarTextoComparacao('BAIXAS LOCALIZADAS');

  /// `true` quando [texto] é especificamente "BAIXAS LOCALIZADAS" — nunca os
  /// outros dois valores de "sem localização conhecida" (INTANGÍVEIS/TI -
  /// SOFTWARE). Usado só para decidir quando anexar a nota de recuperação em
  /// `observacao` — decisão de negócio confirmada: um bem nesta localização
  /// foi baixado por não localização no passado, mas foi encontrado e
  /// retornou à GETEC, então NÃO indica baixa atual. Regra exclusiva da
  /// GETEC, fora da estrutura genérica de [UnitImportProfile].
  static bool ehBaixasLocalizadas(String texto) => normalizarTextoComparacao(texto) == _baixasLocalizadasNormalizado;

  /// Nome OFICIAL cadastrado no InvTec para [texto], se ele for um dos
  /// valores conhecidos da planilha (identidade) ou um apelido conhecido
  /// (ex.: "SITUAÇÃO - PA" → "SITUAÇÃO/SITUADA - PA") — `null` se [texto]
  /// não é um valor de localização física conhecido.
  static String? nomeOficialConhecido(String texto) => perfil.nomeOficialConhecido(texto);

  /// Pré-processa as linhas brutas da planilha (uma única passagem, sem
  /// N+1) antes de entregá-las ao `ImportAnalyzer` genérico: aplica a regra
  /// do "10". Não mexe na coluna de localização em si: a resolução contra
  /// `Localizacao` acontece depois, fora do `ImportAnalyzer` genérico (ver
  /// `PatrimonioImportController`).
  static GetecLinhasPreparadas prepararLinhas({
    required List<List<Object?>> linhas,
    required int indiceCabecalho,
    required ImportColumnMapping mapeamento,
  }) {
    final preparo = perfil.prepararLinhas(linhas: linhas, indiceCabecalho: indiceCabecalho, mapeamento: mapeamento);
    return GetecLinhasPreparadas(linhas: preparo.linhas);
  }

  /// Localizações únicas da planilha com sua contagem — uma única
  /// varredura, nunca linha-a-linha contra o banco.
  static List<GetecLocalizacaoEncontrada> localizacoesUnicas({
    required List<List<Object?>> linhas,
    required int indiceCabecalho,
    required int colunaLocalizacao,
  }) {
    final resultado = UnitImportProfile.localizacoesUnicas(
      linhas: linhas,
      indiceCabecalho: indiceCabecalho,
      colunaLocalizacao: colunaLocalizacao,
    );
    return resultado.map((r) => GetecLocalizacaoEncontrada(texto: r.texto, contagem: r.contagem)).toList();
  }

  /// Resolve [texto] contra uma `Localizacao` ativa (por nome ou sigla)
  /// dentro da gerência já carregada.
  static Localizacao? resolverLocalizacao(String texto, List<Localizacao> localizacoesDaGerencia) =>
      perfil.resolverLocalizacao(texto, localizacoesDaGerencia);

  /// `true` se [texto] já resolve sozinho contra uma localização ativa da
  /// gerência, já tem um mapeamento manual escolhido, ou já foi
  /// explicitamente decidido "importar sem localização".
  static bool localizacaoResolvida(
    String texto,
    List<Localizacao> localizacoesDaGerencia,
    Map<String, String> mapeamentoLocalizacoes,
    Set<String> localizacoesSemMapeamento,
  ) => perfil.localizacaoResolvida(texto, localizacoesDaGerencia, mapeamentoLocalizacoes, localizacoesSemMapeamento);

  /// Preserva o tombamento anterior em `observacao`, combinando de forma
  /// legível com qualquer observação já existente e sem duplicar a mesma
  /// anotação (nem ao atualizar um patrimônio já existente). Regra
  /// exclusiva da GETEC (a planilha tem uma coluna "Tomb anterior" própria),
  /// fora da estrutura genérica.
  static String? mesclarObservacaoComTombamentoAnterior({
    required String? observacaoBase,
    required String? tombamentoAnteriorTexto,
  }) {
    final valor = tombamentoAnteriorTexto?.trim();
    if (valor == null || valor.isEmpty) return observacaoBase;

    final anotacao = 'Tombamento anterior: $valor';
    final base = observacaoBase?.trim();
    if (base == null || base.isEmpty) return anotacao;
    if (base.contains(anotacao)) return base;
    return '$base\n$anotacao';
  }

  static const _notaRecuperacaoBaixasLocalizadas =
      'Bem anteriormente baixado por não localização; localizado novamente e retornado à GETEC nesta carga.';

  /// Preserva no histórico, via `observacao` (campo já existente — sem
  /// alterar schema), o contexto de que este bem esteve marcado como
  /// "BAIXAS LOCALIZADAS" — mesmo padrão de
  /// [mesclarObservacaoComTombamentoAnterior] (combina com o que já existe,
  /// nunca duplica a mesma anotação, mesmo ao atualizar um patrimônio já
  /// existente). Não afeta status nem localização — só documentação textual.
  static String? mesclarObservacaoComRecuperacaoBaixasLocalizadas({
    required String? observacaoBase,
    required bool eraBaixasLocalizadas,
  }) {
    if (!eraBaixasLocalizadas) return observacaoBase;

    final base = observacaoBase?.trim();
    if (base == null || base.isEmpty) return _notaRecuperacaoBaixasLocalizadas;
    if (base.contains(_notaRecuperacaoBaixasLocalizadas)) return base;
    return '$base\n$_notaRecuperacaoBaixasLocalizadas';
  }
}

/// Resultado de [GetecImportProfile.prepararLinhas]: as linhas já com a
/// regra do "10" aplicada.
class GetecLinhasPreparadas {
  const GetecLinhasPreparadas({required this.linhas});

  final List<List<Object?>> linhas;
}

class GetecLocalizacaoEncontrada {
  const GetecLocalizacaoEncontrada({required this.texto, required this.contagem});

  final String texto;
  final int contagem;
}
