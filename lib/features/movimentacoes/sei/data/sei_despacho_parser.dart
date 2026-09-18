import '../../domain/movimentacao.dart';
import '../application/sei_documento_parser.dart';
import '../domain/sei_documento_extraido.dart';
import '../domain/sei_item_extraido.dart';

/// Vocabulário de "início de equipamento" usado só para localizar onde a
/// TABELA de bens realmente começa (nunca para classificar o tipo do
/// patrimônio — isso é decisão do cadastro, não deste parser). PROMPT 11.1,
/// seção 9: o cabeçalho da tabela ("Equipamento/Patrimônio/Chamado/4Biz/SEI")
/// também contém dígitos ("4Biz") que sujariam a extração se não fosse
/// descartado antes de começar — por isso ancoramos o início real dos dados
/// na primeira palavra de equipamento reconhecida, pulando cabeçalho e
/// preâmbulo inteiros.
///
/// Limitação conhecida (a documentar no relatório): um documento cujo
/// primeiro bem da tabela usa um nome de equipamento fora desta lista não
/// tem sua primeira linha localizada corretamente — a lista deve crescer
/// conforme novos documentos reais forem processados.
const _vocabularioEquipamentos = [
  'Monitor',
  'Desktop',
  'Notebook',
  'Estabilizador',
  'Nobreak',
  'No-break',
  'Impressora',
  'Scanner',
  'Computador',
  'Webcam',
  'Roteador',
  'Switch',
  'Projetor',
  'Telefone',
  'Central',
  'Servidor',
  'Storage',
  'Tablet',
  'CPU',
];

/// Palavras que, em documentos da administração pública de Goiás/SEI,
/// tipicamente iniciam o nome por extenso de uma unidade (usadas só para
/// reconhecer onde o texto da "Unidade de Origem" termina e o da "Unidade
/// Destino" começa — seção 9/13).
const _iniciosDeUnidade = [
  'Ger[êe]ncia',
  'Diretoria',
  'Superintend[êe]ncia',
  'Secretaria',
  'Departamento',
  'Coordenadoria',
  'Assessoria',
  'N[úu]cleo',
  'Centro',
  'Procuradoria',
  'Ouvidoria',
  'Controladoria',
  'Ag[êe]ncia',
];

final _origemPattern = RegExp(
  '([A-ZÀ-Ü]{2,10})\\s*[-–]\\s*([\\s\\S]{0,140}?)(?=${_iniciosDeUnidade.join('|')})',
);
final _destinoPattern = RegExp(r'^([\s\S]*?)\s*[–\-]\s*([A-ZÀ-Ü]{2,12})\b');
final _chamadoPattern = RegExp(r'^\s*(\d{3,5})\b');

/// PROMPT 11.1.1, seção 3: sinal PRIMÁRIO para localizar onde a tabela de
/// bens começa — o próprio cabeçalho de colunas ("Unidade de Origem",
/// "Unidade Destino", "Chamado"), nunca o vocabulário fechado de
/// equipamentos. Propositalmente NÃO inclui "Patrimônio": no PDF real esse
/// termo sai intercalado com "Equipamento" ("EquipamenPtaotrimônio"), então
/// exigi-lo quebraria justamente o documento de referência. "SEI" ao final é
/// opcional (cobre o rótulo "4Biz/SEI" que só aparece nesta variante de
/// documento) — quando ausente, o vocabulário auxiliar (abaixo) ainda cobre
/// o restante do lixo de cabeçalho.
final _cabecalhoTabelaPattern = RegExp(
  r'Origem[\s\S]{0,100}?Destino[\s\S]{0,150}?Chamado(?:[\s\S]{0,60}?SEI\b)?',
  caseSensitive: false,
);

/// Comprimento típico de um número de patrimônio NESTA organização —
/// usado só como sinal de confiança, nunca mais como filtro absoluto
/// (PROMPT 11.1.1, seção 4: "evitar length == 7 como única regra
/// estrutural"). Um documento futuro de outra organização pode ter
/// patrimônios com outro comprimento; o analyzer, que já tem os números
/// reais do InvTec em mãos, é quem confirma um candidato atípico.
const _comprimentoTipicoPatrimonio = 7;
const _comprimentoCandidatoMinimo = 4;
const _comprimentoCandidatoMaximo = 10;

final _rodapeDespachoPattern = RegExp(
  r'Despacho\s+(\d+)\s*\((\d+)\)\s*SEI\s+(\d+)(?:\s*/\s*pg\.?\s*\d+)?',
  caseSensitive: false,
);
final _processoPattern = RegExp(r'Processo\s*n[ºo°]?\s*(\d{5,20})', caseSensitive: false);
final _assuntoPattern = RegExp(r'Assunto:\s*([^\n]+)');
final _despachoNumeroFormatadoPattern = RegExp(
  r'DESPACHO\s*N[ºo°]?\s*([\d]+/[\d]+/[A-ZÀ-Ü0-9/\-]+)',
  caseSensitive: false,
);
final _signatarioPattern = RegExp(r'\(Assinado Eletronicamente\)\s*\n?\s*([A-ZÀ-Ü][A-ZÀ-Ü \.]{4,80})');
final _unidadeEmissoraPattern = RegExp(r'\n(GER[ÊE]NCIA[^\n]{0,80})\n');

String _colapsarEspacos(String texto) => texto.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Implementação determinística do parser SEI (PROMPT 11.1, seções 9-14) —
/// nunca depende de regex "cega", nem de split por espaço, nem de número
/// fixo de linhas por bem. Reconhece explicitamente só
/// "Despacho — Transferência de patrimônio" nesta V1 (seção 12); qualquer
/// outro assunto fica com [SeiDocumentoExtraido.tipoMovimentacaoInferido]
/// nulo, nunca uma adivinhação.
class SeiDeterministicParser implements SeiDocumentoParser {
  const SeiDeterministicParser();

  @override
  Future<SeiDocumentoExtraido> analisar({
    required String nomeArquivo,
    required int tamanhoBytes,
    required String hashSha256,
    required List<String> textoPorPagina,
  }) async {
    final avisos = <String>[];
    final textoCompleto = textoPorPagina.join('\n');

    final rodape = _rodapeDespachoPattern.firstMatch(textoCompleto);
    final numeroDocumentoFormatadoMatch = _despachoNumeroFormatadoPattern.firstMatch(textoCompleto);
    final processoMatch = _processoPattern.firstMatch(textoCompleto);
    final assuntoMatch = _assuntoPattern.firstMatch(textoCompleto);
    final signatarioMatch = _signatarioPattern.firstMatch(textoCompleto);
    final unidadeEmissoraMatch = _unidadeEmissoraPattern.firstMatch(textoCompleto);

    final numeroDocumentoSei = rodape?.group(2);
    final numeroProcesso = rodape?.group(3) ?? processoMatch?.group(1);
    final assunto = assuntoMatch != null ? _colapsarEspacos(assuntoMatch.group(1)!) : null;

    final tipoDocumento = numeroDocumentoFormatadoMatch != null || rodape != null
        ? SeiTipoDocumento.despacho
        : SeiTipoDocumento.desconhecido;

    // Seção 12: só classifica quando há evidência textual explícita —
    // "Assunto: Transferência de patrimônio" — nunca por suposição.
    MovimentacaoTipo? tipoMovimentacaoInferido;
    final assuntoNormalizado = assunto?.toLowerCase() ?? '';
    if (assuntoNormalizado.contains('transferência') || assuntoNormalizado.contains('transferencia')) {
      if (assuntoNormalizado.contains('patrim')) {
        tipoMovimentacaoInferido = MovimentacaoTipo.transferencia;
      }
    }
    if (tipoMovimentacaoInferido == null) {
      avisos.add(
        assunto == null
            ? 'Não foi possível identificar o assunto do documento — tipo de movimentação não inferido.'
            : 'Assunto "$assunto" não corresponde a um tipo de movimentação suportado nesta versão (só '
                  'Transferência de patrimônio).',
      );
    }

    if (numeroProcesso == null) avisos.add('Número do processo SEI não foi identificado no documento.');
    if (numeroDocumentoSei == null) avisos.add('Número do documento SEI não foi identificado no documento.');

    final itens = _extrairItens(textoPorPagina, avisos);

    return SeiDocumentoExtraido(
      nomeArquivo: nomeArquivo,
      tamanhoBytes: tamanhoBytes,
      quantidadePaginas: textoPorPagina.length,
      hashSha256: hashSha256,
      numeroProcesso: numeroProcesso,
      numeroDocumentoSei: numeroDocumentoSei,
      tipoDocumento: tipoDocumento,
      numeroDocumentoFormatado: numeroDocumentoFormatadoMatch?.group(1),
      assunto: assunto,
      unidadeEmissora: unidadeEmissoraMatch != null ? _colapsarEspacos(unidadeEmissoraMatch.group(1)!) : null,
      signatario: signatarioMatch != null ? _colapsarEspacos(signatarioMatch.group(1)!) : null,
      tipoMovimentacaoInferido: tipoMovimentacaoInferido,
      itens: itens,
      avisos: avisos,
    );
  }

  /// Localiza onde a tabela de bens começa de verdade (PROMPT 11.1.1, seção
  /// 3). Sinal PRIMÁRIO: o cabeçalho de colunas ("Unidade de Origem",
  /// "Unidade Destino", "Chamado") — nunca depende do vocabulário fechado de
  /// equipamentos para isso. O vocabulário só refina a posição exata quando
  /// a palavra reconhecida aparece logo após o cabeçalho (pula lixo de
  /// cabeçalho remanescente, ex.: "4Biz/SEI", com mais precisão do que
  /// simplesmente parar no fim do cabeçalho). Um equipamento fora do
  /// vocabulário NUNCA faz o parser perder o documento inteiro: sem
  /// refinamento, cai para o fim do próprio cabeçalho reconhecido.
  int? _inicioDaTabela(String texto) {
    final cabecalho = _cabecalhoTabelaPattern.firstMatch(texto);
    final aposCabecalho = cabecalho?.end ?? 0;

    var melhorVocabulario = -1;
    for (final palavra in _vocabularioEquipamentos) {
      final matches = RegExp('\\b$palavra\\b', caseSensitive: false).allMatches(texto, aposCabecalho);
      if (matches.isNotEmpty && (melhorVocabulario == -1 || matches.first.start < melhorVocabulario)) {
        melhorVocabulario = matches.first.start;
      }
    }

    if (melhorVocabulario != -1 && melhorVocabulario - aposCabecalho <= 400) return melhorVocabulario;
    if (cabecalho != null) return aposCabecalho;
    // Último recurso (comportamento antigo): nem o cabeçalho de colunas nem
    // um equipamento conhecido logo após ele foram reconhecidos — ainda
    // assim tenta achar QUALQUER ocorrência do vocabulário no documento
    // inteiro antes de desistir de vez.
    if (melhorVocabulario != -1) return melhorVocabulario;
    return null;
  }

  List<SeiItemExtraido> _extrairItens(List<String> textoPorPagina, List<String> avisosDocumento) {
    // Concatena preservando um marcador de página, para localizar depois em
    // qual página cada item começou (seção 6: `paginaOrigem`). O rodapé
    // repetido em toda página ("Despacho 577 (95955192) SEI
    // 202600017000011 / pg. N") é removido ANTES de concatenar — senão seus
    // próprios dígitos (despacho/documento/processo/página) contaminariam a
    // zona equipamento+patrimônio do primeiro item da página seguinte
    // (seção 9: quebra de página é justamente um dos casos que o parser
    // precisa tolerar).
    final buffer = StringBuffer();
    final offsetsDePagina = <int>[];
    for (final pagina in textoPorPagina) {
      offsetsDePagina.add(buffer.length);
      buffer.write(pagina.replaceAll(_rodapeDespachoPattern, ''));
      buffer.write('\n');
    }
    final textoCompleto = buffer.toString();

    int paginaPara(int offset) {
      var pagina = 1;
      for (var i = 0; i < offsetsDePagina.length; i++) {
        if (offset >= offsetsDePagina[i]) pagina = i + 1;
      }
      return pagina;
    }

    final inicioTabela = _inicioDaTabela(textoCompleto);
    if (inicioTabela == null) {
      avisosDocumento.add(
        'Não foi possível localizar a tabela de bens no documento (nenhum equipamento reconhecido).',
      );
      return const [];
    }

    final origemMatches = _origemPattern.allMatches(textoCompleto, inicioTabela).toList();
    if (origemMatches.isEmpty) {
      avisosDocumento.add('Não foi possível localizar nenhuma linha da tabela de bens (padrão de origem não encontrado).');
      return const [];
    }

    final itens = <SeiItemExtraido>[];
    var zonaEquipPatrimonio = textoCompleto.substring(inicioTabela, origemMatches.first.start);

    for (var i = 0; i < origemMatches.length; i++) {
      final origemMatch = origemMatches[i];
      final origemTexto = _colapsarEspacos('${origemMatch.group(1)} - ${origemMatch.group(2)}');

      final restoInicio = origemMatch.end;
      final restoFim = i + 1 < origemMatches.length ? origemMatches[i + 1].start : textoCompleto.length;
      final resto = textoCompleto.substring(restoInicio, restoFim);

      final destinoMatch = _destinoPattern.firstMatch(resto);
      String? destinoTexto;
      String aposDestino = resto;
      var confiancaDestino = SeiConfianca.alta;
      if (destinoMatch != null) {
        destinoTexto = _colapsarEspacos('${destinoMatch.group(1)} - ${destinoMatch.group(2)}');
        aposDestino = resto.substring(destinoMatch.end);
      } else {
        confiancaDestino = SeiConfianca.baixa;
      }

      final chamadoMatch = _chamadoPattern.firstMatch(aposDestino);
      final chamado = chamadoMatch?.group(1);
      final proximaZona = aposDestino.substring(chamadoMatch?.end ?? 0);

      final (equipamento, patrimonio, confiancaPatrimonio, observacoes) = _extrairEquipamentoPatrimonio(
        zonaEquipPatrimonio,
      );

      itens.add(
        SeiItemExtraido(
          linha: i + 1,
          paginaOrigem: paginaPara(origemMatch.start),
          equipamento: equipamento,
          numeroPatrimonio: patrimonio,
          unidadeOrigemTexto: origemTexto,
          unidadeDestinoTexto: destinoTexto,
          numeroChamado: chamado,
          confiancaPatrimonio: confiancaPatrimonio,
          confiancaDestino: confiancaDestino,
          observacoesParsing: observacoes,
        ),
      );

      zonaEquipPatrimonio = proximaZona;
    }

    return itens;
  }

  /// Separa "equipamento" (letras) de "patrimônio" (dígitos) dentro de uma
  /// mesma zona de texto SEM assumir que os dois nunca aparecem intercalados
  /// (seção 9 — ex.: "Estabilizador" + "3152941" podem chegar como
  /// "Estabilizado3r152941"). PROMPT 11.1.1, seção 4: nunca trata "length ==
  /// 7" como a única regra estrutural — distingue CANDIDATO (plausível pela
  /// posição/contexto, comprimento incomum) de CONFIRMADO (bate no
  /// comprimento típico desta organização). Quem eleva um candidato atípico
  /// a confiável é o [SeiDocumentoAnalyzer], cruzando contra o InvTec.
  (String?, String?, SeiConfianca, List<String>) _extrairEquipamentoPatrimonio(String zona) {
    final semDigitos = _colapsarEspacos(zona.replaceAll(RegExp(r'[0-9]'), ''));
    final equipamento = semDigitos.isEmpty ? null : semDigitos;
    final observacoes = <String>[];

    final runs = RegExp(r'\d+').allMatches(zona).map((m) => m.group(0)!).toList();
    final todosDigitos = runs.join();

    // 1) Um único run contíguo de dígitos plausível — o caso comum de uma
    //    linha bem formada, sem nenhum outro número (chamado/processo/
    //    documento SEI) vazando para dentro da zona (seção 4: "não
    //    confundir com processo SEI/documento SEI/chamado/ano").
    if (runs.length == 1) {
      final unico = runs.single;
      if (unico.length == _comprimentoTipicoPatrimonio) {
        return (equipamento, unico, SeiConfianca.alta, observacoes);
      }
      if (unico.length >= _comprimentoCandidatoMinimo && unico.length <= _comprimentoCandidatoMaximo) {
        observacoes.add(
          'Número de patrimônio encontrado com ${unico.length} dígitos nesta linha (típico nesta organização: '
          '$_comprimentoTipicoPatrimonio) — candidato a confirmar pelo cruzamento com o InvTec.',
        );
        return (equipamento, unico, SeiConfianca.baixa, observacoes);
      }
    }

    // 2) Nenhum run isolado plausível, mas a concatenação de TODOS os
    //    dígitos da zona bate exatamente no comprimento típico e não é
    //    contígua no texto original — dígito intercalado com o texto do
    //    equipamento (o glitch real da seção 9).
    if (todosDigitos.length == _comprimentoTipicoPatrimonio && !zona.contains(todosDigitos)) {
      observacoes.add(
        'Número de patrimônio ($todosDigitos) reconstruído a partir de dígitos intercalados com texto do '
        'equipamento no PDF — conferir contra o documento original.',
      );
      return (equipamento, todosDigitos, SeiConfianca.media, observacoes);
    }

    // 3) Múltiplos runs sem candidato isolado plausível: NUNCA concatena
    //    tudo cegamente (isso misturaria patrimônio com um chamado/processo
    //    que tenha vazado para a zona) — escolhe o run mais PRÓXIMO do
    //    comprimento típico como candidato e ignora os demais.
    if (runs.length > 1) {
      final candidato = runs.reduce(
        (a, b) =>
            (a.length - _comprimentoTipicoPatrimonio).abs() <= (b.length - _comprimentoTipicoPatrimonio).abs()
            ? a
            : b,
      );
      if (candidato.length >= _comprimentoCandidatoMinimo && candidato.length <= _comprimentoCandidatoMaximo) {
        observacoes.add(
          'Mais de um número encontrado nesta linha (${runs.join(", ")}) — usado "$candidato" como candidato a '
          'patrimônio por ser o mais próximo do comprimento típico ($_comprimentoTipicoPatrimonio dígitos); '
          'confira contra o documento original.',
        );
        return (equipamento, candidato, SeiConfianca.baixa, observacoes);
      }
    }

    observacoes.add(
      todosDigitos.isEmpty
          ? 'Nenhum número de patrimônio encontrado nesta linha.'
          : 'Não foi possível identificar um número de patrimônio plausível nesta linha (dígitos encontrados: '
                '$todosDigitos).',
    );
    return (equipamento, null, SeiConfianca.baixa, observacoes);
  }
}
