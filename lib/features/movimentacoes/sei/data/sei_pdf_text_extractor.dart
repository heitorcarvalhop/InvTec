import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../../../../core/utils/file_hash.dart';

/// Erro de leitura do PDF (PROMPT 11.1, seção 4) — nunca um
/// `PostgrestException`/erro de rede: é sempre um problema do ARQUIVO local
/// (vazio, protegido, corrompido, sem camada de texto), mensagem já em
/// PT-BR para mostrar direto na UI.
class SeiPdfLeituraException implements Exception {
  const SeiPdfLeituraException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Resultado bruto da leitura do PDF — texto por página (1 entrada por
/// página, na ordem do documento) + metadados de arquivo. Nenhuma
/// interpretação de conteúdo acontece aqui; isso é responsabilidade do
/// `SeiDocumentoParser` (separação da seção 5).
class SeiPdfLido {
  const SeiPdfLido({required this.textoPorPagina, required this.quantidadePaginas, required this.hashSha256});

  final List<String> textoPorPagina;
  final int quantidadePaginas;
  final String hashSha256;
}

/// Extração de texto de um PDF local (PROMPT 11.1, seção 4/5) — camada
/// isolada em torno da biblioteca de PDF escolhida (`pdfrx`), para que o
/// resto do recurso (parser, analyzer, UI) nunca dependa diretamente dela.
/// Só leitura de arquivo local: nenhuma chamada de rede, nenhum serviço
/// externo, nenhuma escrita.
abstract class SeiPdfTextExtractor {
  Future<SeiPdfLido> extrair(Uint8List bytes);
}

/// Implementação real usando `pdfrx` (PDFium via FFI) — funciona em
/// Windows/macOS/Linux/Android/iOS/Web sem chave de licença nem serviço
/// pago (ver relatório do PROMPT 11.1 para a justificativa da escolha).
class SeiPdfTextExtractorPdfrx implements SeiPdfTextExtractor {
  const SeiPdfTextExtractorPdfrx();

  @override
  Future<SeiPdfLido> extrair(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const SeiPdfLeituraException('O arquivo selecionado está vazio.');
    }

    PdfDocument documento;
    try {
      documento = await PdfDocument.openData(
        bytes,
        // Nunca pede senha ao usuário nesta V1 — um PDF protegido só é
        // relatado como tal (seção 4), nunca uma tentativa de "adivinhar" a
        // senha.
        passwordProvider: () => null,
      );
    } on PdfPasswordException {
      throw const SeiPdfLeituraException('Este PDF está protegido por senha e não pode ser lido nesta versão.');
    } on PdfException catch (e) {
      throw SeiPdfLeituraException('Não foi possível abrir o PDF: ${e.message}');
    } catch (_) {
      throw const SeiPdfLeituraException('Não foi possível abrir o PDF selecionado — o arquivo pode estar corrompido.');
    }

    try {
      final textoPorPagina = <String>[];
      for (final pagina in documento.pages) {
        final texto = await pagina.loadStructuredText();
        textoPorPagina.add(texto.fullText);
      }

      final temTextoExtraivel = textoPorPagina.any((texto) => texto.trim().isNotEmpty);
      if (!temTextoExtraivel) {
        // Seção 29: nunca tenta OCR improvisado — só relata a limitação.
        throw const SeiPdfLeituraException(
          'Não foi possível extrair texto deste documento.\nEste PDF pode ser digitalizado ou não possuir '
          'camada de texto.',
        );
      }

      return SeiPdfLido(
        textoPorPagina: textoPorPagina,
        quantidadePaginas: documento.pages.length,
        hashSha256: sha256Hex(bytes),
      );
    } finally {
      await documento.dispose();
    }
  }
}
