import 'package:csv/csv.dart';

import 'retificacao_csv_linha.dart';

/// Cabeçalho EXATO esperado (ordem importa) — qualquer desvio aborta o
/// parse inteiro com uma mensagem clara, nunca tenta "adivinhar" colunas
/// fora de ordem ou ausentes.
const _cabecalhoEsperado = [
  'ID patrimônio no InvTec',
  'Tombamento oficial (texto)',
  'Tombamento atual no InvTec',
  'Descrição oficial',
  'Setor atual (InvTec)',
  'Unidade correta (sigla)',
  'Unidade correta (nome)',
  'Localização atual no InvTec',
  'Localização na planilha',
  'Localização planejada',
  'Série InvTec',
  'Série oficial',
  'Tombamento anterior planilha',
  'Status tombamento anterior',
  'Status cruzamento',
  'Status da revisão',
  'Observação / justificativa',
];

/// Falha ao interpretar o CSV — nunca uma linha "pulada" silenciosamente;
/// qualquer desvio do layout esperado interrompe o parse inteiro, porque um
/// desalinhamento de colunas poderia fazer um texto de outra coluna ser
/// lido como `patrimonioId` ou `unidadeCorretaSigla` sem nenhum aviso.
class RetificacaoCsvFormatoInvalidoException implements Exception {
  const RetificacaoCsvFormatoInvalidoException(this.mensagem);
  final String mensagem;

  @override
  String toString() => 'RetificacaoCsvFormatoInvalidoException: $mensagem';
}

/// Decodifica `InvTec_plano_reclassificacao_104.csv` (separador `;`, igual
/// à exportação do Excel em pt-BR — ver [Csv.excel]) em
/// [RetificacaoCsvLinha]s. PURO: nenhuma chamada de rede, nenhuma resolução
/// contra o InvTec (isso é `RetificacaoComparador`) — só decodifica texto.
class RetificacaoCsvParser {
  const RetificacaoCsvParser._();

  static List<RetificacaoCsvLinha> parse(String conteudo) {
    // `autoDetect: false` força exatamente `;` — nunca cai para `,` por
    // engano se uma linha não tiver nenhum `;` (ex.: arquivo truncado).
    // `dynamicTyping` fica no padrão `false`: cada célula é sempre `String`,
    // nunca convertida para número — "003636982" não pode perder os zeros
    // à esquerda só por decodificação.
    final conversor = Csv(fieldDelimiter: ';', autoDetect: false);
    final linhasCruas = conversor.decoder
        .convert(conteudo)
        .where((linha) => linha.isNotEmpty && linha.any((celula) => celula.toString().trim().isNotEmpty))
        .toList();

    if (linhasCruas.isEmpty) {
      throw const RetificacaoCsvFormatoInvalidoException('Arquivo vazio ou sem nenhuma linha reconhecível.');
    }

    final cabecalho = linhasCruas.first.map((c) => c.toString().trim()).toList();
    if (cabecalho.length != _cabecalhoEsperado.length ||
        !List.generate(_cabecalhoEsperado.length, (i) => cabecalho[i] == _cabecalhoEsperado[i]).every((ok) => ok)) {
      throw RetificacaoCsvFormatoInvalidoException(
        'Cabeçalho do CSV não corresponde ao layout esperado de '
        '${_cabecalhoEsperado.length} colunas. Encontrado: ${cabecalho.join(" | ")}',
      );
    }

    final resultado = <RetificacaoCsvLinha>[];
    for (var i = 1; i < linhasCruas.length; i++) {
      final numeroLinha = i + 1; // 1-based, cabeçalho = linha 1
      final campos = linhasCruas[i].map((c) => c.toString().trim()).toList();

      if (campos.length != _cabecalhoEsperado.length) {
        throw RetificacaoCsvFormatoInvalidoException(
          'Linha $numeroLinha tem ${campos.length} colunas; esperado ${_cabecalhoEsperado.length}.',
        );
      }

      String? opcional(String v) => v.isEmpty ? null : v;

      final patrimonioId = campos[0];
      final tombamentoOficial = campos[1];
      final tombamentoAtual = campos[2];
      final setorAtual = campos[4];
      final siglaDestino = campos[5];
      final nomeDestino = campos[6];

      if (patrimonioId.isEmpty) {
        throw RetificacaoCsvFormatoInvalidoException('Linha $numeroLinha: "ID patrimônio no InvTec" vazio.');
      }
      if (tombamentoAtual.isEmpty) {
        throw RetificacaoCsvFormatoInvalidoException('Linha $numeroLinha: "Tombamento atual no InvTec" vazio.');
      }
      if (setorAtual.isEmpty) {
        throw RetificacaoCsvFormatoInvalidoException('Linha $numeroLinha: "Setor atual (InvTec)" vazio.');
      }
      if (siglaDestino.isEmpty) {
        throw RetificacaoCsvFormatoInvalidoException('Linha $numeroLinha: "Unidade correta (sigla)" vazio.');
      }

      resultado.add(
        RetificacaoCsvLinha(
          numeroLinha: numeroLinha,
          patrimonioId: patrimonioId,
          tombamentoOficial: tombamentoOficial,
          tombamentoAtualInvtec: tombamentoAtual,
          descricaoOficial: campos[3],
          setorAtualTexto: setorAtual,
          unidadeCorretaSigla: siglaDestino,
          unidadeCorretaNome: nomeDestino,
          localizacaoAtualTexto: opcional(campos[7]),
          localizacaoPlanilhaTexto: opcional(campos[8]),
          localizacaoPlanejadaTexto: opcional(campos[9]),
          serieInvtec: opcional(campos[10]),
          serieOficial: opcional(campos[11]),
          tombamentoAnteriorPlanilha: opcional(campos[12]),
          statusTombamentoAnterior: opcional(campos[13]),
          statusCruzamento: opcional(campos[14]),
          statusRevisao: opcional(campos[15]),
          observacao: opcional(campos[16]),
        ),
      );
    }

    return resultado;
  }
}
