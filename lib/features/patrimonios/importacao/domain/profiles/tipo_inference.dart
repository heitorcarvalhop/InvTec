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
    // Variantes reais de licença Office sem a palavra "microsoft" (achado
    // no diagnóstico com a planilha real da GETEC) — frases explícitas,
    // nunca a palavra "office" isolada (evita falso positivo em algo como
    // "cadeira para home office", que é mobiliário/localização).
    'office home and business',
    'office 2019 professional',
    'office professional',
    'office 365',
    // Erro de digitação real encontrado na planilha da GETEC ("BUSSINES"
    // em vez de "BUSINESS") — variante de grafia exata (PROMPT 8.12,
    // auditoria 8.11), não uma regra genérica de "office" isolado.
    'office home and bussines',
  ]),
  const _RegraInferencia('Nobreak', ['nobreak', 'ups']),
  // Inclui a forma plural encontrada na planilha real ("ESTABILIZADORES
  // PROGRESSIVE III") — variante explícita, não um matching de radical.
  const _RegraInferencia('Estabilizador', ['estabilizador', 'estabilizadores']),
  const _RegraInferencia('Servidor', ['servidor', 'server']),
  const _RegraInferencia('Impressora', ['impressora', 'multifuncional']),
  const _RegraInferencia('Projetor', ['projetor', 'datashow', 'data show']),
  const _RegraInferencia('TV', [
    'televisao',
    'tv',
    // Erro de digitação real encontrado na planilha da GETEC ("ii" duplo)
    // — variante de grafia exata (PROMPT 8.12, auditoria 8.11).
    'televiisor',
  ]),
  const _RegraInferencia('Equipamento de Rede', [
    'switch',
    // Forma plural encontrada na planilha real ("SWITCHES DELL NETWORKING
    // N3024") — variante explícita, mesmo princípio do Estabilizador acima.
    'switches',
    'access point',
    // Equivalente em português de "access point", achado real da planilha
    // GETEC (PROMPT 8.12) — frase específica, não a palavra "acesso" isolada.
    'ponto de acesso',
    'roteador',
    'router',
    'firewall',
    'equipamento de rede',
  ]),
  const _RegraInferencia('Notebook', ['notebook', 'laptop']),
  const _RegraInferencia('Desktop', [
    'desktop',
    'microcomputador',
    // "micro computador"/"micro-computador" (com espaço ou hífen — o hífen
    // já vira espaço em _normalizar) também aparecem na planilha real.
    'micro computador',
    'computador desktop',
    'cpu',
    // Nomes de linha de produto que são SEMPRE um computador desktop —
    // achados reais da planilha GETEC (PROMPT 8.12, auditoria 8.11): risco
    // de falso positivo virtualmente nulo, são nomes de modelo específicos.
    'optiplex',
    // Erro de digitação real encontrado na planilha ("OPTPLEX", sem o "I").
    'optplex',
    'thinkcentre',
    // Grafia real encontrada na planilha GETEC ("THINKCENTER", sem o "R"
    // final de "centre").
    'thinkcenter',
    'compaq pro',
    'estacao de trabalho',
    'workstation',
    'mac mini',
  ]),
  const _RegraInferencia('Monitor', ['monitor']),
  // Itens que o catálogo GETEC explicitamente NÃO quer como tipo próprio
  // (seção 6) — mapeados para "Outros" por regra explícita, não por
  // incerteza (seção 11). Fica ANTES de Mobiliário de propósito: um achado
  // real da planilha ("SCANNER DE MESA, COLOR, DUPLEX 35 PPM") virava
  // Mobiliário porque a palavra "mesa" batia antes da regra de Scanner —
  // termos explícitos de "Outros" têm precedência sobre regras genéricas
  // de Mobiliário que possam capturar uma palavra solta da descrição.
  const _RegraInferencia('Outros', [
    'teclado',
    'mouse',
    'dock station',
    'docking station',
    'scanner',
    'tablet',
    'ar condicionado',
    // Equipamentos de videoconferência (achado real: kits Logitech Group)
    // — frases explícitas e conservadoras; nunca "camera"/"microfone"
    // isolados, que podem significar outro tipo de bem fora desse contexto.
    'videoconferencia',
    'video conferencia',
    'logitech group',
    'expansion mic',
    // Achados reais da planilha GETEC (PROMPT 8.12, auditoria 8.11): nomes
    // de equipamento/eletrodoméstico/ferramenta específicos, claramente
    // fora de todas as outras categorias — risco de falso positivo nulo.
    'frigobar',
    'multimetro',
    'parafusadeira',
    'furadeira',
    'iphone',
    // Variante sem espaço de "ar condicionado" (já uma regra acima) —
    // achado real da planilha.
    'arcondicionado',
  ]),
  const _RegraInferencia('Mobiliário', [
    'armario',
    'mesa',
    'cadeira',
    'estante',
    'gaveteiro',
    'mobiliario',
    'poltrona',
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
      if (contemFraseComoPalavra(normalizado, chave)) {
        return InferenciaTipoResultado(confianca: InferenciaTipoConfianca.confirmada, nomeTipo: regra.nomeTipo);
      }
    }
  }
  return const InferenciaTipoResultado.naoIdentificada();
}

String _normalizar(String valor) {
  return normalizarTextoComparacao(valor).replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
