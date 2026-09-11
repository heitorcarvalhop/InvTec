/// Normalização usada em toda a importação para comparar texto de planilha
/// com nomes já cadastrados (tipos, setores, cabeçalhos): trim, minúsculas,
/// sem acentuação, espaços internos colapsados. Nunca decide nada sozinha —
/// só permite comparar "GETEC" com "getec " ou "Notebook" com "notebook".
String normalizarTextoComparacao(String valor) {
  final semAcentos = _removerAcentos(valor.trim().toLowerCase());
  return semAcentos.replaceAll(RegExp(r'\s+'), ' ');
}

String _removerAcentos(String valor) {
  const comAcento = 'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ';
  const semAcento = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
  final buffer = StringBuffer();
  for (final rune in valor.runes) {
    final char = String.fromCharCode(rune);
    final indice = comAcento.indexOf(char);
    buffer.write(indice == -1 ? char : semAcento[indice]);
  }
  return buffer.toString();
}

/// Distância de Levenshtein — usada apenas para SUGERIR uma correspondência
/// aproximada de tipo/setor (ex.: "Notebok" -> sugestão "Notebook"). A
/// aplicação da sugestão é sempre uma ação explícita do usuário, nunca
/// automática (ver seções 13/14 da especificação de importação).
int distanciaLevenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var linhaAnterior = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final linhaAtual = List<int>.filled(b.length + 1, 0);
    linhaAtual[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final custoSubstituicao = a[i] == b[j] ? 0 : 1;
      final delecao = linhaAnterior[j + 1] + 1;
      final insercao = linhaAtual[j] + 1;
      final substituicao = linhaAnterior[j] + custoSubstituicao;
      linhaAtual[j + 1] = [
        delecao,
        insercao,
        substituicao,
      ].reduce((x, y) => x < y ? x : y);
    }
    linhaAnterior = linhaAtual;
  }
  return linhaAnterior[b.length];
}

/// Entre [candidatos], retorna o mais parecido com [valor] (por
/// [distanciaLevenshtein] sobre o texto normalizado), ou `null` se nenhum
/// estiver dentro de [distanciaMaxima]. Só gera sugestão — nunca resolve
/// sozinho uma ambiguidade.
T? sugerirMaisParecido<T>({
  required String valor,
  required List<T> candidatos,
  required String Function(T) textoDe,
  int distanciaMaxima = 3,
}) {
  final alvo = normalizarTextoComparacao(valor);
  if (alvo.isEmpty || candidatos.isEmpty) return null;

  T? melhor;
  var melhorDistancia = distanciaMaxima + 1;
  for (final candidato in candidatos) {
    final texto = normalizarTextoComparacao(textoDe(candidato));
    final distancia = distanciaLevenshtein(alvo, texto);
    if (distancia < melhorDistancia) {
      melhorDistancia = distancia;
      melhor = candidato;
    }
  }
  return melhorDistancia <= distanciaMaxima ? melhor : null;
}
