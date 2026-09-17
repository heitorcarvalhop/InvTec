import '../text_similarity.dart';

class _RegraSugestao {
  const _RegraSugestao(this.palavraChave, this.nomesTipoSugeridos);

  final String palavraChave;
  final List<String> nomesTipoSugeridos;
}

/// Sugestões NÃO VINCULANTES para os grupos conhecidos dos 37 registros
/// ainda pendentes de tipo (auditoria `getec_auditoria_tipos_pendentes.md`,
/// seção 6 do PROMPT 8.13). Cada entrada é o(s) nome(s) exato(s) do catálogo
/// oficial — ainda precisam ser resolvidos contra os tipos realmente ativos
/// por quem exibir a sugestão (nunca hardcoda um UUID).
///
/// Isto é puramente uma dica visual da tela de resolução manual: NUNCA é
/// usado pelo classificador automático (`tipo_inference.dart`) e NUNCA
/// atribui um tipo sozinho — só o usuário, explicitamente, decide.
final _regrasSugestao = <_RegraSugestao>[
  const _RegraSugestao('rack', ['Equipamento de Rede', 'Mobiliário']),
  const _RegraSugestao('tela interativa', ['TV', 'Monitor']),
  const _RegraSugestao('garantia estendida', ['Outros']),
  const _RegraSugestao('intellitone', ['Equipamento de Rede', 'Outros']),
  const _RegraSugestao('banco de baterias', ['Nobreak', 'Outros']),
  const _RegraSugestao('vnxe1600', ['Servidor']),
  const _RegraSugestao('etiquetadora', ['Impressora']),
  const _RegraSugestao('telefone sem fio', ['Outros']),
  const _RegraSugestao('magic apple keyboard', ['Outros']),
  const _RegraSugestao('magic keyboard aplle', ['Outros']),
  const _RegraSugestao('apple trackpad', ['Outros']),
  const _RegraSugestao('webcam', ['Outros']),
  const _RegraSugestao('escada', ['Outros']),
  const _RegraSugestao('18 btus', ['Outros']),
  const _RegraSugestao('trm200s', ['Monitor']),
  const _RegraSugestao('gaveteorp', ['Mobiliário']),
  const _RegraSugestao('cpui5', ['Desktop']),
];

/// Devolve os nomes de tipo sugeridos (0, 1 ou 2) para [descricao] — vazio
/// quando nenhuma regra conhecida bate; nunca inventa uma sugestão fora
/// desta lista fechada. Quem exibir o resultado deve deixar claro que é uma
/// "Sugestão", nunca uma "Classificação definida" (PROMPT 8.13, seção 6).
List<String> sugerirTiposNaoVinculantes(String? descricao) {
  if (descricao == null) return const [];
  final normalizado = normalizarTextoComparacao(descricao);
  if (normalizado.isEmpty) return const [];
  for (final regra in _regrasSugestao) {
    if (contemFraseComoPalavra(normalizado, regra.palavraChave)) {
      return regra.nomesTipoSugeridos;
    }
  }
  return const [];
}
