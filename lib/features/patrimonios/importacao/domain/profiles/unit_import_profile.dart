import '../../../../localizacoes/domain/localizacao.dart';
import '../../../../setores/domain/setor.dart';
import '../import_column_field.dart';
import '../import_column_mapping.dart';
import '../text_similarity.dart';

/// Descreve, de forma genérica e orientada a dados, as regras de uma
/// planilha legada de UMA unidade/gerência — sigla, cabeçalhos conhecidos,
/// localizações oficiais, apelidos e valores sem localização. Hoje só a
/// GETEC usa uma instância concreta (ver `GetecImportProfile.perfil`), mas
/// a estrutura já está pronta para receber outras unidades sem duplicar a
/// lógica de detecção/mapeamento/resolução de localização.
class UnitImportProfile {
  UnitImportProfile({
    required this.sigla,
    this.nomeCompleto,
    required this.cabecalhosAlvo,
    required Set<String> cabecalhosObrigatoriosDeteccao,
    required this.minimoCamposReconhecidosDeteccao,
    this.camposComSentinelaAusencia = const {},
    bool Function(Object? valor)? ehSentinelaAusencia,
    this.nomesLocalizacoesOficiais = const [],
    Map<String, String> apelidosLocalizacao = const {},
    List<String> valoresSemLocalizacaoConhecidos = const [],
    required this.motivoPadraoSugerido,
    required this.mensagemDeteccao,
  }) : // (campo privado com nome de parâmetro público diferente — um
       // initializing formal `this._cabecalhosObrigatoriosDeteccao` exigiria
       // que os chamadores de outros arquivos passassem um argumento nomeado
       // iniciado com `_`, inacessível fora desta biblioteca.)
       // ignore: prefer_initializing_formals
       _cabecalhosObrigatoriosDeteccao = cabecalhosObrigatoriosDeteccao,
       _ehSentinelaAusencia = ehSentinelaAusencia ?? ((_) => false),
       _nomesOficiaisConhecidos = {
         for (final nome in nomesLocalizacoesOficiais) normalizarTextoComparacao(nome): nome,
       },
       _apelidosConhecidos = {
         for (final entry in apelidosLocalizacao.entries) normalizarTextoComparacao(entry.key): entry.value,
       },
       _semLocalizacaoConhecidos = {
         for (final texto in valoresSemLocalizacaoConhecidos) normalizarTextoComparacao(texto),
       };

  /// Sigla usada para identificar a gerência/unidade entre os setores
  /// ativos carregados do Supabase — `null`/vazia quando a unidade não tem
  /// sigla oficial (ex.: coordenações de unidade de conservação); nesse
  /// caso [encontrarGerencia] usa [nomeCompleto] como identificador.
  final String? sigla;

  /// Nome administrativo completo da unidade — usado por [encontrarGerencia]
  /// (comparação exata após normalização, nunca fuzzy/parcial) sempre que
  /// [sigla] é `null`/vazia. Para unidades com sigla oficial é apenas
  /// documental e não participa da busca.
  final String? nomeCompleto;

  /// Cabeçalhos reais da planilha (já em texto normalizado — ver
  /// [normalizarCabecalho]) → campo do InvTec correspondente.
  final Map<ImportColumnField, String> cabecalhosAlvo;

  final Set<String> _cabecalhosObrigatoriosDeteccao;

  /// Quantidade mínima de colunas de [cabecalhosAlvo] que precisam estar
  /// presentes (além de [_cabecalhosObrigatoriosDeteccao], que são sempre
  /// exigidos) para [detectar] reconhecer o formato.
  final int minimoCamposReconhecidosDeteccao;

  /// Campos em que um valor "sentinela" (ex.: "10") representa ausência de
  /// informação — só se aplica quando este perfil está ativo.
  final Set<ImportColumnField> camposComSentinelaAusencia;

  final bool Function(Object? valor) _ehSentinelaAusencia;

  /// Nomes OFICIAIS de localização física conhecidos para esta unidade,
  /// tal como devem existir em `Localizacao.nome` — usados só para
  /// PROCURAR pelo nome entre as localizações carregadas do Supabase,
  /// nunca um UUID hardcoded.
  final List<String> nomesLocalizacoesOficiais;

  final Map<String, String> _nomesOficiaisConhecidos;
  final Map<String, String> _apelidosConhecidos;
  final Set<String> _semLocalizacaoConhecidos;

  /// Sugestão de motivo padrão da movimentação — nunca aplicada por cima de
  /// um motivo que o usuário já tenha digitado.
  final String motivoPadraoSugerido;

  /// Mensagem exibida quando [detectar] reconhece este formato.
  final String mensagemDeteccao;

  /// Normaliza um cabeçalho de planilha para comparação — sem
  /// acento/maiúsculas/pontuação, pontos e underscores tratados como
  /// espaço, espaços múltiplos colapsados.
  static String normalizarCabecalho(Object? valor) {
    final texto = valor?.toString() ?? '';
    return normalizarTextoComparacao(
      texto,
    ).replaceAll('.', '').replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Reconhece o formato pelo CONJUNTO de cabeçalhos, nunca pelo nome da
  /// aba: exige todos os [_cabecalhosObrigatoriosDeteccao] presentes E ao
  /// menos [minimoCamposReconhecidosDeteccao] das colunas de
  /// [cabecalhosAlvo].
  bool detectar(List<Object?> cabecalho) {
    final normalizados = cabecalho.map(normalizarCabecalho).toSet();

    var encontrados = 0;
    for (final alvo in cabecalhosAlvo.values) {
      if (normalizados.contains(alvo)) encontrados++;
    }

    final todosObrigatorios = _cabecalhosObrigatoriosDeteccao.every(normalizados.contains);
    return todosObrigatorios && encontrados >= minimoCamposReconhecidosDeteccao;
  }

  /// Mapeamento automático sugerido — ainda passa pela etapa de revisão do
  /// usuário como qualquer outra sugestão de mapeamento.
  ImportColumnMapping mapeamentoSugerido(List<Object?> cabecalho) {
    var mapeamento = ImportColumnMapping.vazio;
    for (var coluna = 0; coluna < cabecalho.length; coluna++) {
      final normalizado = normalizarCabecalho(cabecalho[coluna]);
      for (final entry in cabecalhosAlvo.entries) {
        if (entry.value == normalizado) {
          mapeamento = mapeamento.definindo(entry.key, coluna);
          break;
        }
      }
    }
    return mapeamento;
  }

  /// Valor equivalente a uma sentinela de "não informado" (conforme
  /// [_ehSentinelaAusencia]) vira `null`; qualquer outro valor é preservado.
  Object? limparSentinela(Object? valor) {
    if (valor == null) return null;
    return _ehSentinelaAusencia(valor) ? null : valor;
  }

  /// Pré-processa as linhas brutas da planilha (uma única passagem, sem
  /// N+1) aplicando [limparSentinela] às colunas de [camposComSentinelaAusencia]
  /// presentes em [mapeamento].
  UnitLinhasPreparadas prepararLinhas({
    required List<List<Object?>> linhas,
    required int indiceCabecalho,
    required ImportColumnMapping mapeamento,
  }) {
    final colunasComSentinela = [
      for (final campo in camposComSentinelaAusencia)
        if (mapeamento.colunaDe(campo) != null) mapeamento.colunaDe(campo)!,
    ];

    final resultado = <List<Object?>>[];
    for (var i = 0; i < linhas.length; i++) {
      if (i <= indiceCabecalho || colunasComSentinela.isEmpty) {
        resultado.add(linhas[i]);
        continue;
      }

      final nova = List<Object?>.from(linhas[i]);
      for (final coluna in colunasComSentinela) {
        if (coluna < nova.length) nova[coluna] = limparSentinela(nova[coluna]);
      }
      resultado.add(nova);
    }
    return UnitLinhasPreparadas(linhas: resultado);
  }

  /// Encontra a gerência desta unidade entre [setoresAtivos] — por SIGLA
  /// quando [sigla] está preenchida (nunca por UUID hardcoded), OU por NOME
  /// ADMINISTRATIVO COMPLETO (comparação exata após normalização — nunca
  /// fuzzy/parcial) quando a unidade não tem sigla oficial ([sigla]
  /// `null`/vazia). `null` quando não há exatamente UMA gerência
  /// correspondente entre os setores ativos.
  Setor? encontrarGerencia(List<Setor> setoresAtivos) {
    final siglaAtual = sigla;
    if (siglaAtual != null && siglaAtual.trim().isNotEmpty) {
      final alvo = normalizarTextoComparacao(siglaAtual);
      final candidatos = setoresAtivos.where((s) => normalizarTextoComparacao(s.sigla ?? '') == alvo).toList();
      return candidatos.length == 1 ? candidatos.single : null;
    }

    final nome = nomeCompleto;
    if (nome == null || nome.trim().isEmpty) return null;
    final alvoNome = normalizarTextoComparacao(nome);
    final candidatos = setoresAtivos.where((s) => normalizarTextoComparacao(s.nome) == alvoNome).toList();
    return candidatos.length == 1 ? candidatos.single : null;
  }

  /// Nome OFICIAL conhecido para [texto] (identidade ou apelido) — `null` se
  /// [texto] não é um valor de localização física conhecido.
  String? nomeOficialConhecido(String texto) {
    final chave = normalizarTextoComparacao(texto);
    return _apelidosConhecidos[chave] ?? _nomesOficiaisConhecidos[chave];
  }

  /// `true` quando [texto] é um dos valores conhecidos que explicitamente
  /// NÃO representam uma localização física.
  bool ehValorSemLocalizacaoConhecido(String texto) =>
      _semLocalizacaoConhecidos.contains(normalizarTextoComparacao(texto));

  /// Resolve [texto] contra uma `Localizacao` ativa (por nome ou sigla)
  /// dentro da gerência já carregada.
  Localizacao? resolverLocalizacao(String texto, List<Localizacao> localizacoesDaGerencia) {
    final chave = normalizarTextoComparacao(nomeOficialConhecido(texto) ?? texto);
    for (final localizacao in localizacoesDaGerencia) {
      if (normalizarTextoComparacao(localizacao.nome) == chave) return localizacao;
      final siglaLocalizacao = localizacao.sigla;
      if (siglaLocalizacao != null && siglaLocalizacao.trim().isNotEmpty && normalizarTextoComparacao(siglaLocalizacao) == chave) {
        return localizacao;
      }
    }
    return null;
  }

  /// `true` se [texto] já resolve sozinho, já tem um mapeamento manual
  /// escolhido, ou já foi explicitamente decidido "importar sem
  /// localização".
  bool localizacaoResolvida(
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

  /// Localizações únicas da planilha com sua contagem — uma única
  /// varredura, nunca linha-a-linha contra o banco.
  static List<UnitLocalizacaoEncontrada> localizacoesUnicas({
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
          (entry) => UnitLocalizacaoEncontrada(texto: textoOriginalPorChave[entry.key]!, contagem: entry.value),
        )
        .toList()
      ..sort((a, b) => b.contagem.compareTo(a.contagem));
    return resultado;
  }
}

/// Resultado de [UnitImportProfile.prepararLinhas]: as linhas já com os
/// valores sentinela limpos.
class UnitLinhasPreparadas {
  const UnitLinhasPreparadas({required this.linhas});

  final List<List<Object?>> linhas;
}

class UnitLocalizacaoEncontrada {
  const UnitLocalizacaoEncontrada({required this.texto, required this.contagem});

  final String texto;
  final int contagem;
}
