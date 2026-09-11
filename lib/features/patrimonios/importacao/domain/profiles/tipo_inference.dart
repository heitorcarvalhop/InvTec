import '../text_similarity.dart';

/// Nível de confiança da inferência de tipo a partir da descrição (seção 11
/// do perfil GETEC). Não existe um nível "sugerido" à parte: as regras desta
/// primeira fase são determinísticas (palavra-chave presente ou não), então
/// o resultado é sempre CONFIRMADO ou NÃO IDENTIFICADO — nunca aplicamos
/// "Outros" só para esconder incerteza fora das regras explícitas do item 9.
enum InferenciaTipoConfianca { confirmada, naoIdentificada }

class InferenciaTipoResultado {
  const InferenciaTipoResultado({required this.confianca, this.nomeTipo});

  const InferenciaTipoResultado.naoIdentificada()
    : confianca = InferenciaTipoConfianca.naoIdentificada,
      nomeTipo = null;

  final InferenciaTipoConfianca confianca;

  /// Nome exato do catálogo oficial (seção 6) — ainda precisa ser resolvido
  /// contra os tipos realmente ativos no banco por quem chamar esta função;
  /// este módulo não conhece o banco.
  final String? nomeTipo;
}

class _RegraInferencia {
  const _RegraInferencia(this.nomeTipo, this.palavrasChave);

  final String nomeTipo;
  final List<String> palavrasChave;
}

/// Ordem importa (seção 10): categorias mais específicas primeiro, para que
/// "LICENÇA MICROSOFT OFFICE PARA NOTEBOOK" vire Software / Licença em vez
/// de Notebook só porque a palavra "notebook" aparece na descrição.
final _regras = <_RegraInferencia>[
  const _RegraInferencia('Certificado Digital', ['certificado digital']),
  const _RegraInferencia('Software / Licença', [
    'licenca',
    'software',
    'microsoft office',
    'windows',
    'adobe',
  ]),
  const _RegraInferencia('Nobreak', ['nobreak', 'ups']),
  const _RegraInferencia('Estabilizador', ['estabilizador']),
  const _RegraInferencia('Servidor', ['servidor', 'server']),
  const _RegraInferencia('Impressora', ['impressora', 'multifuncional']),
  const _RegraInferencia('Projetor', ['projetor', 'datashow', 'data show']),
  const _RegraInferencia('TV', ['televisao', 'tv']),
  const _RegraInferencia('Equipamento de Rede', [
    'switch',
    'access point',
    'roteador',
    'router',
    'firewall',
    'equipamento de rede',
  ]),
  const _RegraInferencia('Notebook', ['notebook', 'laptop']),
  const _RegraInferencia('Desktop', ['desktop', 'microcomputador', 'computador desktop', 'cpu']),
  const _RegraInferencia('Monitor', ['monitor']),
  const _RegraInferencia('Mobiliário', [
    'armario',
    'mesa',
    'cadeira',
    'estante',
    'gaveteiro',
    'mobiliario',
  ]),
  // Itens que o catálogo GETEC explicitamente NÃO quer como tipo próprio
  // (seção 6) — mapeados para "Outros" por regra explícita, não por
  // incerteza (seção 11).
  const _RegraInferencia('Outros', [
    'teclado',
    'mouse',
    'dock station',
    'docking station',
    'scanner',
    'tablet',
    'ar condicionado',
  ]),
];

/// Infere o tipo de patrimônio a partir do texto livre de [descricao]
/// (seção 8/9) usando só regras determinísticas locais — nenhuma IA externa,
/// nenhuma chamada de rede. Retorna [InferenciaTipoConfianca.naoIdentificada]
/// quando nenhuma regra bate, em vez de adivinhar.
InferenciaTipoResultado inferirTipoPorDescricao(String? descricao) {
  if (descricao == null) return const InferenciaTipoResultado.naoIdentificada();

  final normalizado = _normalizar(descricao);
  if (normalizado.isEmpty) return const InferenciaTipoResultado.naoIdentificada();

  for (final regra in _regras) {
    for (final chave in regra.palavrasChave) {
      if (_contemFrase(normalizado, chave)) {
        return InferenciaTipoResultado(confianca: InferenciaTipoConfianca.confirmada, nomeTipo: regra.nomeTipo);
      }
    }
  }
  return const InferenciaTipoResultado.naoIdentificada();
}

String _normalizar(String valor) {
  return normalizarTextoComparacao(valor).replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// `true` quando [frase] aparece em [texto] como palavra(s) inteira(s) — não
/// como parte de outra palavra (ex.: "cpu" não deve bater dentro de
/// "ocupado"). Implementado sem lookbehind para não depender de suporte a
/// regex avançado.
bool _contemFrase(String texto, String frase) {
  if (frase.isEmpty) return false;
  var inicioBusca = 0;
  while (true) {
    final indice = texto.indexOf(frase, inicioBusca);
    if (indice == -1) return false;

    final antes = indice == 0 ? null : texto[indice - 1];
    final indiceDepois = indice + frase.length;
    final depois = indiceDepois >= texto.length ? null : texto[indiceDepois];

    final antesOk = antes == null || !_ehAlfanumerico(antes);
    final depoisOk = depois == null || !_ehAlfanumerico(depois);
    if (antesOk && depoisOk) return true;

    inicioBusca = indice + 1;
  }
}

bool _ehAlfanumerico(String caractere) => RegExp(r'[a-z0-9]').hasMatch(caractere);
