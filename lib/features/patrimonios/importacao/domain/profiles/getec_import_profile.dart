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

  /// Sugestão de UX (seção 18) — nunca aplicada por cima de um motivo que o
  /// usuário já tenha digitado.
  static const motivoPadraoSugerido = 'Carga inicial do inventário patrimonial da GETEC';

  /// Cabeçalhos reais da planilha (seção 1), já como texto normalizado
  /// (sem acento/maiúsculas/pontuação) → campo do InvTec correspondente.
  static const _cabecalhosAlvo = <ImportColumnField, String>{
    ImportColumnField.numeroPatrimonio: 'tombamento',
    ImportColumnField.tombamentoAnterior: 'tomb anterior',
    ImportColumnField.descricao: 'descricao',
    ImportColumnField.setor: 'localizacao',
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

  /// `true` quando o texto de localização sugere um bem já baixado (seção
  /// 23) — só gera aviso, nunca aplica status BAIXADO automaticamente.
  static bool indicaBaixa(String texto) => normalizarTextoComparacao(texto).contains('baixa');

  /// Pré-processa as linhas brutas da planilha (seção 29: uma única
  /// passagem, sem N+1) antes de entregá-las ao `ImportAnalyzer` genérico:
  /// aplica a regra do "10" (seção 4), substitui o texto de localização
  /// pelo nome do setor escolhido pelo usuário no passo de localizações
  /// (seção 15/16) e sinaliza linhas cuja localização original sugere baixa
  /// (seção 23) — usando o número de linha absoluto (1-based) do arquivo
  /// original, para casar depois com `ImportRow.numeroLinha`.
  static GetecLinhasPreparadas prepararLinhas({
    required List<List<Object?>> linhas,
    required int indiceCabecalho,
    required ImportColumnMapping mapeamento,
    required Map<String, String> mapeamentoLocalizacoes,
  }) {
    final colunaSerie = mapeamento.colunaDe(ImportColumnField.numeroSerie);
    final colunaTombAnterior = mapeamento.colunaDe(ImportColumnField.tombamentoAnterior);
    final colunaLocalizacao = mapeamento.colunaDe(ImportColumnField.setor);

    final resultado = <List<Object?>>[];
    final baixas = <int>{};

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

      if (colunaLocalizacao != null && colunaLocalizacao < nova.length) {
        final textoOriginal = nova[colunaLocalizacao]?.toString().trim();
        if (textoOriginal != null && textoOriginal.isNotEmpty) {
          if (indicaBaixa(textoOriginal)) baixas.add(i + 1);

          final chave = normalizarTextoComparacao(textoOriginal);
          final setorEscolhido = mapeamentoLocalizacoes[chave];
          if (setorEscolhido != null) {
            nova[colunaLocalizacao] = setorEscolhido;
          }
        }
      }

      resultado.add(nova);
    }

    return GetecLinhasPreparadas(linhas: resultado, linhasComPossivelBaixa: baixas);
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

  /// `true` se [texto] já resolveria sozinho contra um setor ativo (nome ou
  /// sigla) ou já tem um mapeamento manual escolhido — usado só para marcar
  /// "OK" no resumo de localizações (seção 15), sem decidir nada sozinho.
  static bool localizacaoResolvida(
    String texto,
    List<Setor> setoresAtivos,
    Map<String, String> mapeamentoLocalizacoes,
  ) {
    final chave = normalizarTextoComparacao(texto);
    if (mapeamentoLocalizacoes.containsKey(chave)) return true;
    for (final setor in setoresAtivos) {
      if (normalizarTextoComparacao(setor.nome) == chave) return true;
      final sigla = setor.sigla;
      if (sigla != null && sigla.trim().isNotEmpty && normalizarTextoComparacao(sigla) == chave) return true;
    }
    return false;
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
}

/// Resultado de [GetecImportProfile.prepararLinhas]: as linhas já com a
/// regra do "10" e o mapeamento de localizações aplicados, e o conjunto de
/// números de linha (1-based, absolutos no arquivo original) cuja
/// localização original sugere baixa.
class GetecLinhasPreparadas {
  const GetecLinhasPreparadas({required this.linhas, required this.linhasComPossivelBaixa});

  final List<List<Object?>> linhas;
  final Set<int> linhasComPossivelBaixa;
}

class GetecLocalizacaoEncontrada {
  const GetecLocalizacaoEncontrada({required this.texto, required this.contagem});

  final String texto;
  final int contagem;
}
