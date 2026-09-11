import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/data/spreadsheet_parser.dart';

Uint8List _gerarXlsx(Map<String, List<List<Object?>>> abas) {
  final excel = xlsx.Excel.createExcel();
  for (final entry in abas.entries) {
    final sheet = excel[entry.key];
    for (final linha in entry.value) {
      sheet.appendRow([
        for (final celula in linha)
          switch (celula) {
            null => null,
            String s => xlsx.TextCellValue(s),
            int i => xlsx.IntCellValue(i),
            DateTime d => xlsx.DateCellValue.fromDateTime(d),
            _ => xlsx.TextCellValue(celula.toString()),
          },
      ]);
    }
  }
  // remove a aba padrão "Sheet1" criada automaticamente quando não usada
  if (!abas.containsKey('Sheet1')) excel.delete('Sheet1');
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  group('formatoPorNomeArquivo', () {
    test('reconhece .xlsx e .csv, ignorando caixa', () {
      expect(formatoPorNomeArquivo('planilha.xlsx'), ImportFileFormat.xlsx);
      expect(formatoPorNomeArquivo('planilha.XLSX'), ImportFileFormat.xlsx);
      expect(formatoPorNomeArquivo('planilha.csv'), ImportFileFormat.csv);
    });

    test('retorna null para formatos não suportados (ex.: .xls)', () {
      expect(formatoPorNomeArquivo('planilha.xls'), isNull);
      expect(formatoPorNomeArquivo('planilha.txt'), isNull);
    });
  });

  group('SpreadsheetParser — XLSX', () {
    test('lê células de texto, número e data corretamente', () async {
      final bytes = _gerarXlsx({
        'Patrimônios': [
          ['Patrimônio', 'Tipo', 'Quantidade', 'Data'],
          ['00045872', 'Notebook', 3, DateTime(2024, 3, 10)],
        ],
      });

      final arquivo = await SpreadsheetParser.parse(bytes, 'inventario.xlsx');

      expect(arquivo.formato, ImportFileFormat.xlsx);
      expect(arquivo.abas, hasLength(1));
      final linhas = arquivo.abas.single.linhas;
      expect(linhas[0], ['Patrimônio', 'Tipo', 'Quantidade', 'Data']);
      expect(linhas[1][0], '00045872');
      expect(linhas[1][1], 'Notebook');
      expect(linhas[1][2], 3);
      expect(linhas[1][3], isA<DateTime>());
      expect(linhas[1][3], DateTime(2024, 3, 10));
    });

    test('lê múltiplas abas preservando os nomes', () async {
      final bytes = _gerarXlsx({
        'GETEC': [
          ['Patrimônio'],
          ['1'],
        ],
        'GEVEV': [
          ['Patrimônio'],
          ['2'],
        ],
      });

      final arquivo = await SpreadsheetParser.parse(bytes, 'multi.xlsx');

      expect(arquivo.abas.map((a) => a.nome), containsAll(['GETEC', 'GEVEV']));
    });

    test('arquivo corrompido gera um erro amigável, sem lançar exceção técnica', () async {
      final bytesInvalidos = Uint8List.fromList(utf8.encode('isto não é um xlsx'));

      await expectLater(
        SpreadsheetParser.parse(bytesInvalidos, 'corrompido.xlsx'),
        throwsA(
          isA<SpreadsheetParseException>().having(
            (e) => e.message,
            'message',
            contains('Não foi possível ler este arquivo'),
          ),
        ),
      );
    });
  });

  group('SpreadsheetParser — CSV', () {
    test('autodetecta separador ponto e vírgula (comum em planilhas BR)', () async {
      final csv = 'Patrimônio;Tipo;Marca\n00045872;Notebook;Dell\n';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      final arquivo = await SpreadsheetParser.parse(bytes, 'inventario.csv');

      final linhas = arquivo.abas.single.linhas;
      expect(linhas[0], ['Patrimônio', 'Tipo', 'Marca']);
      expect(linhas[1], ['00045872', 'Notebook', 'Dell']);
    });

    test('autodetecta separador vírgula', () async {
      final csv = 'Patrimônio,Tipo,Marca\n00045872,Notebook,Dell\n';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      final arquivo = await SpreadsheetParser.parse(bytes, 'inventario.csv');

      final linhas = arquivo.abas.single.linhas;
      expect(linhas[1], ['00045872', 'Notebook', 'Dell']);
    });

    test('respeita delimitador explicitamente forçado pelo usuário', () async {
      // separador real é ";", mas o texto também contém "," dentro de um
      // campo — forçar ";" evita que a vírgula quebre o parsing.
      final csv = 'Patrimônio;Descrição\n1;"Nota, com virgula"\n';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      final arquivo = await SpreadsheetParser.parse(bytes, 'inventario.csv', delimitadorCsv: ';');

      final linhas = arquivo.abas.single.linhas;
      expect(linhas[1], ['1', 'Nota, com virgula']);
    });

    test('remove o BOM UTF-8 quando presente', () async {
      final bomBytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('Patrimônio\n1\n')];
      final bytes = Uint8List.fromList(bomBytes);

      final arquivo = await SpreadsheetParser.parse(bytes, 'inventario.csv');

      expect(arquivo.abas.single.linhas[0], ['Patrimônio']);
    });

    test('preserva número patrimonial com zeros à esquerda como texto', () async {
      final csv = 'Patrimônio\n00045872\n';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      final arquivo = await SpreadsheetParser.parse(bytes, 'inventario.csv');

      expect(arquivo.abas.single.linhas[1][0], '00045872');
    });
  });

  group('SpreadsheetParser — formato não suportado', () {
    test('rejeita extensão desconhecida antes de tentar ler o conteúdo', () async {
      final bytes = Uint8List.fromList(utf8.encode('conteúdo qualquer'));

      await expectLater(
        SpreadsheetParser.parse(bytes, 'planilha.xls'),
        throwsA(
          isA<SpreadsheetParseException>().having(
            (e) => e.message,
            'message',
            contains('.xlsx ou .csv'),
          ),
        ),
      );
    });
  });
}
