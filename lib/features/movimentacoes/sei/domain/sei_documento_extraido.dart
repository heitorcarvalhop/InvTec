import '../../domain/movimentacao.dart';
import 'sei_item_extraido.dart';

/// Tipos de documento SEI que o parser já sabe reconhecer — "desconhecido"
/// nunca vira erro por si só: o documento pode ser analisado mesmo sem tipo
/// reconhecido, só sem [SeiDocumentoExtraido.tipoMovimentacaoInferido].
enum SeiTipoDocumento { despacho, desconhecido }

/// Resultado da extração de um PDF SEI — metadados do documento + itens da
/// tabela de bens (PROMPT 11.1, seção 6). Puramente o que foi lido do PDF:
/// nada aqui foi cruzado com o InvTec (ver `SeiAnaliseResultado`) e nada
/// aqui nunca alimenta uma escrita real.
class SeiDocumentoExtraido {
  const SeiDocumentoExtraido({
    required this.nomeArquivo,
    required this.tamanhoBytes,
    required this.quantidadePaginas,
    required this.hashSha256,
    this.numeroProcesso,
    this.numeroDocumentoSei,
    this.tipoDocumento = SeiTipoDocumento.desconhecido,
    this.numeroDocumentoFormatado,
    this.assunto,
    this.unidadeEmissora,
    this.signatario,
    this.dataDocumento,
    this.tipoMovimentacaoInferido,
    this.itens = const [],
    this.avisos = const [],
  });

  final String nomeArquivo;
  final int tamanhoBytes;
  final int quantidadePaginas;

  /// SHA-256 do arquivo (seção 27) — mantido só no resultado da análise
  /// desta sessão, nunca persistido nesta etapa. Permitirá futuramente
  /// impedir o reprocessamento do mesmo documento.
  final String hashSha256;

  /// Número do processo SEI (ex.: "202600017000011").
  final String? numeroProcesso;

  /// Número do documento SEI (ex.: "95955192") — vira `numero_documento` na
  /// prévia de movimentação (seção 15), nunca confundido com o chamado.
  final String? numeroDocumentoSei;

  final SeiTipoDocumento tipoDocumento;

  /// Identificação legível do documento (ex.: "577/2026/SEMAD/GETEC-12014"
  /// para um Despacho).
  final String? numeroDocumentoFormatado;

  final String? assunto;
  final String? unidadeEmissora;
  final String? signatario;
  final DateTime? dataDocumento;

  /// Só preenchido quando há evidência suficiente (seção 12) — nunca uma
  /// adivinhação. V1 só reconhece TRANSFERENCIA.
  final MovimentacaoTipo? tipoMovimentacaoInferido;

  final List<SeiItemExtraido> itens;

  /// Avisos gerais do documento (não de uma linha específica) — ex.: "não
  /// foi possível identificar o assunto do despacho".
  final List<String> avisos;
}
