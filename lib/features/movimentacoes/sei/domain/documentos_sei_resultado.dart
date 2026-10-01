import 'sei_documento_pendente.dart';

/// Página de documentos SEI pendentes + total real (mesmo padrão de
/// `MovimentacoesResultado`) — [total] é sempre o total da consulta
/// completa no banco, nunca `itens.length`.
class DocumentosSeiResultado {
  const DocumentosSeiResultado({required this.itens, required this.total});

  final List<SeiDocumentoPendente> itens;
  final int total;
}
