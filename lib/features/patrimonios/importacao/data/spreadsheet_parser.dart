import 'dart:convert';

import 'package:excel/excel.dart' as xlsx;
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

enum ImportFileFormat { xlsx, csv }

/// Uma aba já decodificada em linhas/células "planas" (String, num, bool,
/// DateTime ou null) — nunca expõe tipos das bibliotecas `excel`/`csv` para
/// fora da camada de dados (seção 35: "não colocar parser XLSX dentro do
/// widget").
class ImportParsedSheet {
  const ImportParsedSheet({required this.nome, required this.linhas});

  final String nome;
  final List<List<Object?>> linhas;
}

class ImportParsedFile {
  const ImportParsedFile({
    required this.nomeArquivo,
    required this.formato,
    required this.abas,
  });

  final String nomeArquivo;
  final ImportFileFormat formato;
  final List<ImportParsedSheet> abas;
}

/// Erro amigável de leitura de arquivo — nunca deixa uma exceção técnica
/// (do `excel`/`csv`) chegar à UI (seção 41).
class SpreadsheetParseException implements Exception {
  const SpreadsheetParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _mensagemArquivoInvalido =
    'Não foi possível ler este arquivo. Verifique se ele é uma planilha XLSX ou CSV válida.';

/// Deduz o formato só pela extensão do nome do arquivo — os únicos dois
/// formatos suportados nesta etapa (seção 1: não implementar .xls).
ImportFileFormat? formatoPorNomeArquivo(String nomeArquivo) {
  final nome = nomeArquivo.toLowerCase();
  if (nome.endsWith('.xlsx')) return ImportFileFormat.xlsx;
  if (nome.endsWith('.csv')) return ImportFileFormat.csv;
  return null;
}

/// arquivo → células/linhas (seção 35). O parsing pesado (decodificar o
/// XLSX/CSV inteiro) roda em uma isolate via [compute], para não travar a
/// interface com planilhas de milhares de linhas (seção 4).
class SpreadsheetParser {
  const SpreadsheetParser._();

  static Future<ImportParsedFile> parse(
    Uint8List bytes,
    String nomeArquivo, {
    String? delimitadorCsv,
  }) async {
    final formato = formatoPorNomeArquivo(nomeArquivo);
    if (formato == null) {
      throw const SpreadsheetParseException(
        'Formato de arquivo não suportado. Selecione um arquivo .xlsx ou .csv.',
      );
    }

    final abas = formato == ImportFileFormat.xlsx
        ? await compute(_decodeXlsx, bytes)
        : await compute(_decodeCsv, _CsvDecodeArgs(bytes, delimitadorCsv));

    if (abas.isEmpty || abas.every((aba) => aba.linhas.isEmpty)) {
      throw const SpreadsheetParseException('A planilha não contém nenhuma linha de dados.');
    }

    return ImportParsedFile(nomeArquivo: nomeArquivo, formato: formato, abas: abas);
  }
}

List<ImportParsedSheet> _decodeXlsx(Uint8List bytes) {
  final xlsx.Excel excel;
  try {
    excel = xlsx.Excel.decodeBytes(bytes);
  } catch (_) {
    throw const SpreadsheetParseException(_mensagemArquivoInvalido);
  }

  final abas = <ImportParsedSheet>[];
  for (final nomeAba in excel.tables.keys) {
    final sheet = excel.tables[nomeAba];
    if (sheet == null) continue;
    final linhas = sheet.rows.map((linha) => linha.map(_valorCelulaXlsx).toList()).toList();
    abas.add(ImportParsedSheet(nome: nomeAba, linhas: linhas));
  }
  return abas;
}

Object? _valorCelulaXlsx(xlsx.Data? celula) {
  final valor = celula?.value;
  if (valor == null) return null;
  switch (valor) {
    case xlsx.TextCellValue():
      final texto = valor.value.toString();
      return texto.isEmpty ? null : texto;
    case xlsx.IntCellValue():
      return valor.value;
    case xlsx.DoubleCellValue():
      return valor.value;
    case xlsx.BoolCellValue():
      return valor.value;
    // Data "real" do Excel: segura para interpretar diretamente, sem
    // ambiguidade de formato (seção 38).
    case xlsx.DateCellValue():
      return valor.asDateTimeLocal();
    case xlsx.DateTimeCellValue():
      return valor.asDateTimeLocal();
    case xlsx.TimeCellValue():
      return valor.toString();
    case xlsx.FormulaCellValue():
      return valor.formula;
  }
}

class _CsvDecodeArgs {
  const _CsvDecodeArgs(this.bytes, this.delimitador);

  final Uint8List bytes;
  final String? delimitador;
}

List<ImportParsedSheet> _decodeCsv(_CsvDecodeArgs args) {
  final String texto;
  try {
    var bytes = args.bytes;
    // remove o BOM UTF-8, comum em CSV exportado do Excel
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    texto = utf8.decode(bytes);
  } on FormatException {
    throw const SpreadsheetParseException(
      'Não foi possível interpretar a codificação deste arquivo. '
      'Salve-o como CSV UTF-8 e tente novamente.',
    );
  }

  // Planilhas brasileiras frequentemente usam ";" como separador — por
  // isso o padrão é autodetectar em vez de assumir "," (seção 40). Quando
  // o usuário força um delimitador explícito, ele tem prioridade.
  final csv = Csv(
    autoDetect: args.delimitador == null,
    fieldDelimiter: args.delimitador ?? ',',
  );

  final List<List<dynamic>> linhas;
  try {
    linhas = csv.decode(texto);
  } catch (_) {
    throw const SpreadsheetParseException(_mensagemArquivoInvalido);
  }

  return [
    ImportParsedSheet(
      nome: 'CSV',
      linhas: linhas.map((linha) => linha.cast<Object?>()).toList(),
    ),
  ];
}
