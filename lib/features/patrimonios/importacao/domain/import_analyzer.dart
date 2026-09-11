import '../../domain/patrimonio.dart';
import '../../domain/patrimonio_detalhe.dart';
import '../../domain/tipo_patrimonio.dart';
import '../../../setores/domain/setor.dart';
import 'import_column_field.dart';
import 'import_column_mapping.dart';
import 'import_date_parser.dart';
import 'import_defaults.dart';
import 'import_row.dart';
import 'text_similarity.dart';

/// Linhas → validações/duplicidades/resoluções (seção 35). Não faz nenhuma
/// chamada de rede: recebe tipos/setores ativos e os conjuntos de
/// "já existe no banco" já resolvidos em lote pelo controller, e devolve
/// [ImportRow]s totalmente classificados. Puro e testável com fakes.
class ImportAnalyzer {
  const ImportAnalyzer._();

  /// Lê todas as linhas de dados (após [indiceCabecalho]) e produz uma
  /// [ImportRow] por linha não vazia, já com tipo/setor resolvidos,
  /// duplicidade de arquivo marcada e classificação aplicada.
  static List<ImportRow> analisar({
    required List<List<Object?>> linhas,
    required int indiceCabecalho,
    required ImportColumnMapping mapeamento,
    required ImportDefaults padroes,
    required List<TipoPatrimonio> tiposAtivos,
    required List<Setor> setoresAtivos,
    required Map<String, PatrimonioDetalhe> existentesPorNumero,
    required Set<String> numerosSerieExistentesNoBanco,
  }) {
    final inicioDados = indiceCabecalho + 1;
    final dadosBrutos = inicioDados < linhas.length ? linhas.sublist(inicioDados) : const <List<Object?>>[];

    final resultado = <ImportRow>[];
    for (var i = 0; i < dadosBrutos.length; i++) {
      final linhaBruta = dadosBrutos[i];
      if (_linhaVazia(linhaBruta)) continue;

      final celulas = <ImportColumnField, String?>{};
      for (final campo in ImportColumnField.values) {
        final coluna = mapeamento.colunaDe(campo);
        if (coluna == null || coluna >= linhaBruta.length) continue;
        celulas[campo] = celulaParaTexto(linhaBruta[coluna]);
      }

      final linha = ImportRow(
        // 1-based e relativo ao arquivo original (cabeçalho + linhas antes dela).
        numeroLinha: indiceCabecalho + 2 + i,
        celulas: celulas,
      );
      _resolverCampos(linha, linhaBruta, mapeamento, padroes, tiposAtivos, setoresAtivos);
      resultado.add(linha);
    }

    _marcarDuplicadosNoArquivo(resultado);
    _marcarExistentesNoBanco(resultado, existentesPorNumero);
    _marcarPossivelDuplicidadeSerial(resultado, numerosSerieExistentesNoBanco);

    for (final linha in resultado) {
      classificar(linha);
    }
    return resultado;
  }

  /// Recalcula `issues`/`status` de UMA linha a partir dos campos já
  /// resolvidos (id de tipo/setor, decisão de existente, flag de ignorada,
  /// flag de duplicidade de arquivo). Chamada tanto pela análise completa
  /// quanto depois de qualquer decisão manual do usuário — única fonte de
  /// verdade da classificação (seção 20).
  static void classificar(ImportRow linha) {
    linha.issues.clear();

    if (linha.ignoradaManualmente) {
      linha.status = ImportRowStatus.ignorado;
      return;
    }

    // Duplicidade dentro do arquivo é sempre resolvida ANTES de qualquer
    // outra coisa (seção 15 é explícita: crítica) — mesmo que o número já
    // exista no banco, nunca deixamos duas linhas do arquivo apontarem
    // "atualizar" para o mesmo registro simultaneamente sem decisão.
    if (linha.duplicadoNoArquivo) {
      linha.issues.add(
        const ImportIssue(ImportIssueSeverity.erro, 'Número patrimonial duplicado dentro da planilha.'),
      );
      linha.status = ImportRowStatus.erro;
      return;
    }

    // Patrimônio já existente: "atualizar metadados" nunca toca tipo/setor
    // via planilha diretamente (ver PatrimonioRepository.atualizar — não há
    // parâmetro de setor/responsável), então a resolução de tipo/setor da
    // planilha não bloqueia esse caminho.
    if (linha.existenteNoBanco != null) {
      linha.status = linha.acaoExistente == ImportExistingAction.atualizarMetadados
          ? ImportRowStatus.atualizar
          : ImportRowStatus.existente;
      return;
    }

    // Checa o ID resolvido primeiro (não só o texto da linha): um perfil
    // pode ter resolvido o tipo sem que a planilha tivesse uma coluna de
    // tipo mapeada (ex.: inferência por descrição do perfil GETEC) — nesse
    // caso `tipoTexto` fica null mesmo a linha estando pronta.
    if (linha.tipoIdResolvido == null) {
      if (linha.tipoTexto == null || linha.tipoTexto!.trim().isEmpty) {
        linha.issues.add(
          const ImportIssue(ImportIssueSeverity.erro, 'Tipo é obrigatório e está vazio nesta linha.'),
        );
      } else {
        linha.issues.add(
          ImportIssue(ImportIssueSeverity.erro, "Tipo não encontrado: '${linha.tipoTexto}'."),
        );
      }
    }

    if (linha.dataAquisicaoNaoReconhecida) {
      // data_aquisicao é sempre opcional e sem conceito de padrão — nunca
      // bloqueia, só avisa que aquele valor específico foi ignorado.
      linha.issues.add(
        ImportIssue(
          ImportIssueSeverity.aviso,
          "Data de aquisição não reconhecida: '${linha.celulas[ImportColumnField.dataAquisicao]}'.",
        ),
      );
    }

    if (linha.dataEntradaNaoReconhecida) {
      if (linha.usouDataPadrao) {
        linha.issues.add(
          ImportIssue(
            ImportIssueSeverity.aviso,
            "Data de entrada não reconhecida: '${linha.celulas[ImportColumnField.dataEntrada]}' "
                '— será usada a data padrão da importação.',
          ),
        );
      } else {
        linha.issues.add(
          ImportIssue(
            ImportIssueSeverity.erro,
            "Data de entrada não reconhecida: '${linha.celulas[ImportColumnField.dataEntrada]}' "
                'e nenhuma data padrão foi configurada.',
          ),
        );
      }
    }

    final temTextoDeSetor = linha.setorTexto != null && linha.setorTexto!.trim().isNotEmpty;
    if (linha.destinoIdResolvido == null) {
      if (temTextoDeSetor) {
        linha.issues.add(
          ImportIssue(
            ImportIssueSeverity.erro,
            "Setor não encontrado: '${linha.setorTexto}' e nenhum setor padrão foi configurado.",
          ),
        );
      } else {
        linha.issues.add(
          const ImportIssue(
            ImportIssueSeverity.erro,
            'Nenhum setor de destino informado nem definido como padrão da importação.',
          ),
        );
      }
    } else if (temTextoDeSetor && linha.usouDestinoPadrao) {
      linha.issues.add(
        ImportIssue(
          ImportIssueSeverity.aviso,
          "Setor '${linha.setorTexto}' não encontrado — foi usado o setor padrão da importação.",
        ),
      );
    }

    // Origem é obrigatória para um patrimônio NOVO nesta importação — mais
    // restritivo que a RPC (que aceita origem nula), por decisão explícita:
    // toda linha nova precisa de uma origem rastreável, da própria linha ou
    // de um padrão configurado; nunca fica sem resolução.
    final temTextoDeOrigem = linha.origemTexto != null && linha.origemTexto!.trim().isNotEmpty;
    if (linha.origemIdResolvido == null) {
      if (temTextoDeOrigem) {
        linha.issues.add(
          ImportIssue(
            ImportIssueSeverity.erro,
            "Setor de origem não encontrado: '${linha.origemTexto}' e nenhuma origem padrão foi configurada.",
          ),
        );
      } else {
        linha.issues.add(
          const ImportIssue(
            ImportIssueSeverity.erro,
            'Nenhuma origem informada nem definida como padrão da importação.',
          ),
        );
      }
    } else if (temTextoDeOrigem && linha.usouOrigemPadrao) {
      linha.issues.add(
        ImportIssue(
          ImportIssueSeverity.aviso,
          "Setor de origem '${linha.origemTexto}' não encontrado — foi usada a origem padrão da importação.",
        ),
      );
    }

    // Checado antes de mandar para a RPC: cadastrar_patrimonio rejeita
    // origem == destino numa ENTRADA — nunca deixar a RPC falhar por isso.
    if (linha.origemIdResolvido != null &&
        linha.destinoIdResolvido != null &&
        linha.origemIdResolvido == linha.destinoIdResolvido) {
      linha.issues.add(
        const ImportIssue(ImportIssueSeverity.erro, 'A origem e o destino precisam ser diferentes.'),
      );
    }

    if (linha.possivelDuplicidadeSerial) {
      linha.issues.add(
        ImportIssue(
          ImportIssueSeverity.aviso,
          "Número de série '${linha.numeroSerie}' já aparece em outro patrimônio.",
        ),
      );
    }

    if (linha.possivelBaixa) {
      linha.issues.add(
        const ImportIssue(
          ImportIssueSeverity.aviso,
          'Esta localização sugere que o patrimônio pode estar baixado. A carga '
              'inicial não aplicará status Baixado automaticamente.',
        ),
      );
    }

    if (linha.temErro) {
      linha.status = ImportRowStatus.erro;
    } else if (linha.temAviso) {
      linha.status = ImportRowStatus.aviso;
    } else {
      linha.status = ImportRowStatus.pronto;
    }
  }

  static void _resolverCampos(
    ImportRow linha,
    List<Object?> linhaBruta,
    ImportColumnMapping mapeamento,
    ImportDefaults padroes,
    List<TipoPatrimonio> tiposAtivos,
    List<Setor> setoresAtivos,
  ) {
    Object? bruto(ImportColumnField campo) {
      final coluna = mapeamento.colunaDe(campo);
      if (coluna == null || coluna >= linhaBruta.length) return null;
      return linhaBruta[coluna];
    }

    linha.numeroPatrimonio = linha.celulas[ImportColumnField.numeroPatrimonio];
    linha.numeroPatrimonioNormalizado = normalizarNumeroPatrimonio(linha.numeroPatrimonio);
    linha.numeroSerie = linha.celulas[ImportColumnField.numeroSerie];
    linha.marca = linha.celulas[ImportColumnField.marca];
    linha.modelo = linha.celulas[ImportColumnField.modelo];
    linha.descricao = linha.celulas[ImportColumnField.descricao];
    linha.observacao = linha.celulas[ImportColumnField.observacao];

    final motivoLinha = linha.celulas[ImportColumnField.motivo];
    final motivoPadrao = padroes.motivoPadrao;
    if (motivoLinha != null) {
      linha.motivo = motivoLinha;
    } else if (motivoPadrao != null && motivoPadrao.trim().isNotEmpty) {
      linha.motivo = motivoPadrao;
      linha.usouMotivoPadrao = true;
    }

    linha.dataAquisicao = _celulaParaData(bruto(ImportColumnField.dataAquisicao));
    linha.dataAquisicaoNaoReconhecida =
        linha.celulas.containsKey(ImportColumnField.dataAquisicao) && linha.dataAquisicao == null;

    final dataEntradaLida = _celulaParaData(bruto(ImportColumnField.dataEntrada));
    final textoDataEntrada = linha.celulas[ImportColumnField.dataEntrada];
    if (dataEntradaLida != null) {
      linha.dataEntrada = dataEntradaLida;
    } else {
      // Só é "não reconhecida" quando havia texto e ele não pôde ser
      // interpretado — célula vazia/coluna não mapeada é simplesmente
      // "sem data informada", não um valor inválido (seção 4).
      linha.dataEntradaNaoReconhecida = textoDataEntrada != null;
      final padraoData = padroes.dataPadrao;
      if (padraoData != null) {
        linha.dataEntrada = padraoData;
        linha.usouDataPadrao = true;
      }
      // sem padrão configurado: dataEntrada fica null. Se havia texto não
      // reconhecido, isso vira ERRO em classificar(); se a célula estava
      // simplesmente vazia, não é erro — cadastrar_patrimonio usa now().
    }

    final responsavelLinha = linha.celulas[ImportColumnField.responsavel];
    final responsavelPadrao = padroes.responsavelDestinoPadrao;
    if (responsavelLinha != null) {
      linha.responsavelDestino = responsavelLinha;
    } else if (responsavelPadrao != null && responsavelPadrao.trim().isNotEmpty) {
      linha.responsavelDestino = responsavelPadrao;
      linha.usouResponsavelPadrao = true;
    }

    linha.tipoTexto = linha.celulas[ImportColumnField.tipo];
    final tipoTexto = linha.tipoTexto;
    if (tipoTexto != null) {
      final alvo = normalizarTextoComparacao(tipoTexto);
      for (final tipo in tiposAtivos) {
        if (normalizarTextoComparacao(tipo.nome) == alvo) {
          linha.tipoIdResolvido = tipo.id;
          break;
        }
      }
      if (linha.tipoIdResolvido == null) {
        linha.tipoIdSugerido = sugerirMaisParecido(
          valor: tipoTexto,
          candidatos: tiposAtivos,
          textoDe: (t) => t.nome,
        )?.id;
      }
    }

    linha.setorTexto = linha.celulas[ImportColumnField.setor];
    final destino = _resolverSetorComPadrao(linha.setorTexto, padroes.destinoPadraoId, setoresAtivos);
    linha.destinoIdResolvido = destino.id;
    linha.destinoIdSugerido = destino.sugerido;
    linha.usouDestinoPadrao = destino.usouPadrao;

    linha.origemTexto = linha.celulas[ImportColumnField.origem];
    final origem = _resolverSetorComPadrao(linha.origemTexto, padroes.origemPadraoId, setoresAtivos);
    linha.origemIdResolvido = origem.id;
    linha.origemIdSugerido = origem.sugerido;
    linha.usouOrigemPadrao = origem.usouPadrao;
  }

  /// Resolve um texto de setor (destino OU origem) contra os setores
  /// ativos; se o texto não bater com nada (ou estiver ausente), cai para
  /// o padrão da importação quando configurado. "Usou padrão" só fica
  /// marcado quando o padrão foi de fato necessário — nunca quando o
  /// texto já resolveu sozinho (seções 1/2: linha > padrão > manual).
  static _ResolucaoSetor _resolverSetorComPadrao(
    String? texto,
    String? padraoId,
    List<Setor> setoresAtivos,
  ) {
    if (texto != null && texto.trim().isNotEmpty) {
      final resolvido = _resolverSetor(texto, setoresAtivos);
      if (resolvido != null) return _ResolucaoSetor(id: resolvido);

      final sugestao = _sugerirSetor(texto, setoresAtivos);
      if (padraoId != null) {
        return _ResolucaoSetor(id: padraoId, sugerido: sugestao, usouPadrao: true);
      }
      return _ResolucaoSetor(sugerido: sugestao);
    }

    if (padraoId != null) {
      return _ResolucaoSetor(id: padraoId, usouPadrao: true);
    }
    return const _ResolucaoSetor();
  }

  static void _marcarDuplicadosNoArquivo(List<ImportRow> linhas) {
    final grupos = <String, List<ImportRow>>{};
    for (final linha in linhas) {
      final numero = linha.numeroPatrimonioNormalizado;
      if (numero == null) continue;
      grupos.putIfAbsent(numero, () => []).add(linha);
    }
    for (final grupo in grupos.values) {
      if (grupo.length <= 1) continue;
      for (final linha in grupo) {
        linha.duplicadoNoArquivo = true;
      }
    }
  }

  static void _marcarExistentesNoBanco(
    List<ImportRow> linhas,
    Map<String, PatrimonioDetalhe> existentesPorNumero,
  ) {
    for (final linha in linhas) {
      final numero = linha.numeroPatrimonioNormalizado;
      if (numero == null) continue;
      linha.existenteNoBanco = existentesPorNumero[numero];
    }
  }

  static void _marcarPossivelDuplicidadeSerial(
    List<ImportRow> linhas,
    Set<String> numerosSerieExistentesNoBanco,
  ) {
    final contagemNoArquivo = <String, int>{};
    for (final linha in linhas) {
      final serial = linha.numeroSerie;
      if (serial == null || serial.isEmpty) continue;
      contagemNoArquivo.update(serial, (valor) => valor + 1, ifAbsent: () => 1);
    }

    for (final linha in linhas) {
      // já é um patrimônio existente: manter/atualizar não cria duplicidade nova.
      if (linha.existenteNoBanco != null) continue;
      final serial = linha.numeroSerie;
      if (serial == null || serial.isEmpty) continue;
      final duplicadoNoArquivo = (contagemNoArquivo[serial] ?? 0) > 1;
      final existeNoBanco = numerosSerieExistentesNoBanco.contains(serial);
      linha.possivelDuplicidadeSerial = duplicadoNoArquivo || existeNoBanco;
    }
  }

  static String? _resolverSetor(String texto, List<Setor> setores) {
    final alvo = normalizarTextoComparacao(texto);
    for (final setor in setores) {
      if (normalizarTextoComparacao(setor.nome) == alvo) return setor.id;
      final sigla = setor.sigla;
      if (sigla != null && sigla.trim().isNotEmpty && normalizarTextoComparacao(sigla) == alvo) {
        return setor.id;
      }
    }
    return null;
  }

  static String? _sugerirSetor(String texto, List<Setor> setores) {
    const distanciaMaxima = 3;
    final alvo = normalizarTextoComparacao(texto);
    if (alvo.isEmpty || setores.isEmpty) return null;

    Setor? melhor;
    var melhorDistancia = distanciaMaxima + 1;
    for (final setor in setores) {
      var distancia = distanciaLevenshtein(alvo, normalizarTextoComparacao(setor.nome));
      final sigla = setor.sigla;
      if (sigla != null && sigla.trim().isNotEmpty) {
        final distanciaSigla = distanciaLevenshtein(alvo, normalizarTextoComparacao(sigla));
        if (distanciaSigla < distancia) distancia = distanciaSigla;
      }
      if (distancia < melhorDistancia) {
        melhorDistancia = distancia;
        melhor = setor;
      }
    }
    return melhorDistancia <= distanciaMaxima ? melhor?.id : null;
  }

  static bool _linhaVazia(List<Object?> linha) {
    return linha.every((celula) {
      if (celula == null) return true;
      if (celula is String) return celula.trim().isEmpty;
      return false;
    });
  }

  /// Conversão genérica de célula → texto, reaproveitada pelo controller
  /// para varreduras leves (ex.: coletar números patrimoniais candidatos
  /// antes da análise completa, para a consulta em lote ao banco).
  static String? celulaParaTexto(Object? valor) {
    if (valor == null) return null;
    if (valor is String) {
      final texto = valor.trim();
      return texto.isEmpty ? null : texto;
    }
    if (valor is DateTime) return valor.toIso8601String();
    if (valor is double) {
      return valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString();
    }
    return valor.toString();
  }

  static DateTime? _celulaParaData(Object? valor) {
    if (valor == null) return null;
    if (valor is DateTime) return valor;
    if (valor is String) return interpretarDataTexto(valor);
    // número puro numa coluna de data: ambíguo (poderia ser um serial do
    // Excel não decodificado como data) — não converter silenciosamente.
    return null;
  }
}

/// Resultado de [ImportAnalyzer._resolverSetorComPadrao]: o id resolvido
/// (da linha ou do padrão), uma sugestão por similaridade quando o texto da
/// linha não bateu com nada, e se o padrão foi realmente usado (para
/// diferenciar "OK direto" de "OK via padrão" na revisão — seção 6).
class _ResolucaoSetor {
  const _ResolucaoSetor({this.id, this.sugerido, this.usouPadrao = false});

  final String? id;
  final String? sugerido;
  final bool usouPadrao;
}
