import '../../../../localizacoes/domain/localizacao.dart';
import '../../../../setores/domain/setor.dart';
import '../import_column_field.dart';
import '../import_column_mapping.dart';
import '../text_similarity.dart';

/// Regras específicas da planilha real usada pela GETEC ("aba
/// RelatorioBemPermanente") — nada aqui é usado a menos que o perfil seja
/// explicitamente detectado E ativado pelo usuário (seção 27); o importador
/// genérico (`ImportAnalyzer`, `ImportColumnField`) nunca importa nada deste
/// arquivo e continua funcionando de forma idêntica sem ele.
class GetecImportProfile {
  const GetecImportProfile._();

  static const mensagemDeteccao = 'Formato de inventário GETEC reconhecido.';

  /// Sugestão de UX (seção 18, revisada na seção 14 da correção de
  /// modelagem de localizações) — nunca aplicada por cima de um motivo que
  /// o usuário já tenha digitado. Deixa explícito no próprio motivo da
  /// movimentação que a origem histórica é desconhecida, já que a planilha
  /// não tem nenhuma coluna de origem.
  static const motivoPadraoSugerido =
      'Carga inicial do inventário patrimonial da GETEC - origem histórica não informada.';

  /// Sigla usada para identificar a gerência GETEC entre os setores ativos
  /// carregados do Supabase (PROMPT 8.13.1) — mesmo critério já usado no
  /// preflight real (`ImportPreflight.validarGerenciaUnica(sigla: 'GETEC')`).
  static const siglaGerencia = 'GETEC';

  /// Encontra a gerência GETEC entre [setoresAtivos] — por SIGLA, nunca por
  /// UUID hardcoded (quem chamar recebe o `Setor` real, com o id
  /// verdadeiro). `null` quando não há exatamente UMA gerência com essa
  /// sigla entre os setores ativos: para este perfil, todo bem da carga
  /// pertence à GETEC, então uma ausência ou ambiguidade é bloqueante, nunca
  /// resolvida silenciosamente.
  static Setor? encontrarGerenciaGetec(List<Setor> setoresAtivos) {
    final alvo = normalizarTextoComparacao(siglaGerencia);
    final candidatos = setoresAtivos.where(
      (s) => normalizarTextoComparacao(s.sigla ?? '') == alvo,
    ).toList();
    return candidatos.length == 1 ? candidatos.single : null;
  }

  /// Cabeçalhos reais da planilha (seção 1), já como texto normalizado
  /// (sem acento/maiúsculas/pontuação) → campo do InvTec correspondente.
  static const _cabecalhosAlvo = <ImportColumnField, String>{
    ImportColumnField.numeroPatrimonio: 'tombamento',
    ImportColumnField.tombamentoAnterior: 'tomb anterior',
    ImportColumnField.descricao: 'descricao',
    // A coluna "localizacao" da planilha é a Localização dentro da
    // gerência GETEC (seção 30) — NUNCA o setor/gerência em si. A gerência
    // da carga inteira é fixa (destino padrão da importação, configurado
    // pelo usuário como GETEC), nunca derivada desta coluna.
    ImportColumnField.localizacao: 'localizacao',
    ImportColumnField.marca: 'marca',
    ImportColumnField.numeroSerie: 'n serie',
  };

  /// Campos em que "10" é um marcador legado de "não informado" (seção 4) —
  /// só se aplica quando este perfil está ativo, nunca globalmente.
  static const camposComSentinela10 = {ImportColumnField.numeroSerie, ImportColumnField.tombamentoAnterior};

  static String _normalizarCabecalho(Object? valor) {
    final texto = valor?.toString() ?? '';
    return normalizarTextoComparacao(
      texto,
    ).replaceAll('.', '').replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Seção 1/27: reconhece o formato pelo CONJUNTO de cabeçalhos, nunca pelo
  /// nome da aba. Exige as duas colunas mais distintivas (tombamento +
  /// descrição) e ao menos 4 das 6 colunas conhecidas — suficiente para não
  /// disparar em falso numa planilha genérica que só por acaso tenha uma
  /// coluna "Descrição" ou "Marca".
  static bool detectar(List<Object?> cabecalho) {
    final normalizados = cabecalho.map(_normalizarCabecalho).toSet();

    var encontrados = 0;
    for (final alvo in _cabecalhosAlvo.values) {
      if (normalizados.contains(alvo)) encontrados++;
    }

    return normalizados.contains('tombamento') && normalizados.contains('descricao') && encontrados >= 4;
  }

  /// Mapeamento automático sugerido (seção 2) — ainda passa pela etapa de
  /// revisão do usuário como qualquer outra sugestão de mapeamento.
  static ImportColumnMapping mapeamentoSugerido(List<Object?> cabecalho) {
    var mapeamento = ImportColumnMapping.vazio;
    for (var coluna = 0; coluna < cabecalho.length; coluna++) {
      final normalizado = _normalizarCabecalho(cabecalho[coluna]);
      for (final entry in _cabecalhosAlvo.entries) {
        if (entry.value == normalizado) {
          mapeamento = mapeamento.definindo(entry.key, coluna);
          break;
        }
      }
    }
    return mapeamento;
  }

  /// Seção 4: valor textual/numericamente equivalente a "10" vira ausência
  /// de informação nos campos [camposComSentinela10].
  static Object? limparSentinela10(Object? valor) {
    if (valor == null) return null;
    if (valor is num && valor == 10) return null;
    if (valor is String && valor.trim() == '10') return null;
    return valor;
  }

  // ---------------------------------------------------------------------
  // Mapeamento oficial de localizações (PROMPT 8.9)
  // ---------------------------------------------------------------------

  /// Os 15 nomes OFICIAIS de localização física cadastrados no InvTec para
  /// a gerência GETEC, tal como devem existir em `Localizacao.nome`. Chave
  /// já normalizada (ver `normalizarTextoComparacao`) para comparação; o
  /// valor é o nome oficial exato — usado só para PROCURAR pelo nome entre
  /// as localizações carregadas do Supabase, nunca um UUID hardcoded (a
  /// resolução real de UUID acontece em [resolverLocalizacao], contra a
  /// lista de `Localizacao` já carregada da gerência).
  static final Map<String, String> _nomesOficiaisConhecidos = {
    for (final nome in const [
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
    ])
      normalizarTextoComparacao(nome): nome,
  };

  /// Formas antigas/alternativas usadas na planilha para um nome oficial já
  /// listado em [_nomesOficiaisConhecidos] — hoje só "SITUAÇÃO - PA"
  /// (planilha) → "SITUAÇÃO/SITUADA - PA" (nome oficial cadastrado no
  /// InvTec; PA = Parque Amazônia). Chave também normalizada.
  static final Map<String, String> _apelidosConhecidos = {
    normalizarTextoComparacao('SITUAÇÃO - PA'): 'SITUAÇÃO/SITUADA - PA',
  };

  /// Valores da coluna "localizacao" que a GETEC usa para dizer
  /// explicitamente que aquele registro NÃO tem localização física
  /// associada — nunca tratados como pendência nem erro: a ausência de
  /// localização é a decisão CONHECIDA e correta para eles.
  static final Set<String> _semLocalizacaoConhecidos = {
    for (final texto in const ['INTANGÍVEIS', 'TI - SOFTWARE', 'BAIXAS LOCALIZADAS']) normalizarTextoComparacao(texto),
  };

  /// `true` quando [texto] é um dos valores conhecidos que explicitamente
  /// NÃO representam uma localização física — usado para decidir
  /// `localizacaoDestinoId = null` sem gerar pendência nem erro (nunca um
  /// caso "não resolvido").
  static bool ehValorSemLocalizacaoConhecido(String texto) =>
      _semLocalizacaoConhecidos.contains(normalizarTextoComparacao(texto));

  static final String _baixasLocalizadasNormalizado = normalizarTextoComparacao('BAIXAS LOCALIZADAS');

  /// `true` quando [texto] é especificamente "BAIXAS LOCALIZADAS" — nunca os
  /// outros dois valores de [_semLocalizacaoConhecidos] (INTANGÍVEIS/TI -
  /// SOFTWARE). Usado só para decidir quando anexar a nota de recuperação em
  /// `observacao` (PROMPT 8.12) — decisão de negócio confirmada: um bem
  /// nesta localização foi baixado por não localização no passado, mas foi
  /// encontrado e retornou à GETEC, então NÃO indica baixa atual.
  static bool ehBaixasLocalizadas(String texto) => normalizarTextoComparacao(texto) == _baixasLocalizadasNormalizado;

  /// Nome OFICIAL cadastrado no InvTec para [texto], se ele for um dos 15
  /// valores conhecidos da planilha (identidade) ou um apelido conhecido
  /// (ex.: "SITUAÇÃO - PA" → "SITUAÇÃO/SITUADA - PA") — `null` se [texto]
  /// não é um valor de localização física conhecido. Nunca aproxima nem
  /// adivinha: só reconhece o conjunto explicitamente listado acima.
  static String? nomeOficialConhecido(String texto) {
    final chave = normalizarTextoComparacao(texto);
    return _apelidosConhecidos[chave] ?? _nomesOficiaisConhecidos[chave];
  }

  /// Pré-processa as linhas brutas da planilha (seção 29: uma única
  /// passagem, sem N+1) antes de entregá-las ao `ImportAnalyzer` genérico:
  /// aplica a regra do "10" (seção 4). Não mexe na coluna de localização em
  /// si: a resolução contra `Localizacao` acontece depois, fora do
  /// `ImportAnalyzer` genérico (ver `PatrimonioImportController`).
  ///
  /// PROMPT 8.12: esta função sinalizava anteriormente linhas cuja
  /// localização continha a palavra "baixa" como "possível baixa" — removido
  /// porque, para a GETEC, "BAIXAS LOCALIZADAS" é uma decisão de negócio
  /// conhecida (bem recuperado/relocalizado, nunca baixado atualmente), não
  /// um indício real de baixa. Ver `ehBaixasLocalizadas`.
  static GetecLinhasPreparadas prepararLinhas({
    required List<List<Object?>> linhas,
    required int indiceCabecalho,
    required ImportColumnMapping mapeamento,
  }) {
    final colunaSerie = mapeamento.colunaDe(ImportColumnField.numeroSerie);
    final colunaTombAnterior = mapeamento.colunaDe(ImportColumnField.tombamentoAnterior);

    final resultado = <List<Object?>>[];

    for (var i = 0; i < linhas.length; i++) {
      if (i <= indiceCabecalho) {
        resultado.add(linhas[i]);
        continue;
      }

      final nova = List<Object?>.from(linhas[i]);

      if (colunaSerie != null && colunaSerie < nova.length) {
        nova[colunaSerie] = limparSentinela10(nova[colunaSerie]);
      }
      if (colunaTombAnterior != null && colunaTombAnterior < nova.length) {
        nova[colunaTombAnterior] = limparSentinela10(nova[colunaTombAnterior]);
      }

      resultado.add(nova);
    }

    return GetecLinhasPreparadas(linhas: resultado);
  }

  /// Localizações únicas da planilha com sua contagem (seção 15) — uma
  /// única varredura, nunca linha-a-linha contra o banco.
  static List<GetecLocalizacaoEncontrada> localizacoesUnicas({
    required List<List<Object?>> linhas,
    required int indiceCabecalho,
    required int colunaLocalizacao,
  }) {
    final contagemPorChave = <String, int>{};
    final textoOriginalPorChave = <String, String>{};

    for (var i = indiceCabecalho + 1; i < linhas.length; i++) {
      final linha = linhas[i];
      if (colunaLocalizacao >= linha.length) continue;
      final texto = linha[colunaLocalizacao]?.toString().trim();
      if (texto == null || texto.isEmpty) continue;

      final chave = normalizarTextoComparacao(texto);
      contagemPorChave.update(chave, (valor) => valor + 1, ifAbsent: () => 1);
      textoOriginalPorChave.putIfAbsent(chave, () => texto);
    }

    final resultado = contagemPorChave.entries
        .map(
          (entry) => GetecLocalizacaoEncontrada(texto: textoOriginalPorChave[entry.key]!, contagem: entry.value),
        )
        .toList()
      ..sort((a, b) => b.contagem.compareTo(a.contagem));
    return resultado;
  }

  /// Resolve [texto] contra uma `Localizacao` ativa (por nome ou sigla)
  /// dentro da gerência já carregada — usado tanto para marcar "OK" no
  /// resumo de localizações (seção 15) quanto para achar automaticamente
  /// as que já existem, sem exigir mapeamento manual repetido.
  static Localizacao? resolverLocalizacao(String texto, List<Localizacao> localizacoesDaGerencia) {
    // Canonicaliza um apelido/forma antiga conhecida (ex.: "SITUAÇÃO - PA")
    // para o nome oficial ANTES de comparar — nunca resolve para um UUID
    // direto, só troca o texto a procurar entre as localizações já
    // carregadas da gerência.
    final chave = normalizarTextoComparacao(nomeOficialConhecido(texto) ?? texto);
    for (final localizacao in localizacoesDaGerencia) {
      if (normalizarTextoComparacao(localizacao.nome) == chave) return localizacao;
      final sigla = localizacao.sigla;
      if (sigla != null && sigla.trim().isNotEmpty && normalizarTextoComparacao(sigla) == chave) {
        return localizacao;
      }
    }
    return null;
  }

  /// `true` se [texto] já resolve sozinho contra uma localização ativa da
  /// gerência, já tem um mapeamento manual escolhido, ou já foi
  /// explicitamente decidido "importar sem localização" — usado só para
  /// marcar "OK" no resumo de localizações (seção 15/32), sem decidir nada
  /// sozinho.
  static bool localizacaoResolvida(
    String texto,
    List<Localizacao> localizacoesDaGerencia,
    Map<String, String> mapeamentoLocalizacoes,
    Set<String> localizacoesSemMapeamento,
  ) {
    final chave = normalizarTextoComparacao(texto);
    if (mapeamentoLocalizacoes.containsKey(chave)) return true;
    if (localizacoesSemMapeamento.contains(chave)) return true;
    if (ehValorSemLocalizacaoConhecido(texto)) return true;
    return resolverLocalizacao(texto, localizacoesDaGerencia) != null;
  }

  /// Seção 5: preserva o tombamento anterior em `observacao`, combinando de
  /// forma legível com qualquer observação já existente e sem duplicar a
  /// mesma anotação (nem ao atualizar um patrimônio já existente).
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

  /// PROMPT 8.12: preserva no histórico, via `observacao` (campo já
  /// existente — sem alterar schema), o contexto de que este bem esteve
  /// marcado como "BAIXAS LOCALIZADAS" — mesmo padrão de
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
