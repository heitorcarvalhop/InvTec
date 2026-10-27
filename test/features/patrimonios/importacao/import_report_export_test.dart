import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_report_export.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';

ImportRow _linha({
  required int numeroLinha,
  String? numeroPatrimonio,
  required bool sucesso,
  String? patrimonioId,
  String? mensagemErro,
}) {
  final linha = ImportRow(numeroLinha: numeroLinha, celulas: const {});
  linha.numeroPatrimonio = numeroPatrimonio;
  linha.resultado = ImportRowResult(sucesso: sucesso, patrimonioId: patrimonioId, mensagemErro: mensagemErro);
  return linha;
}

void main() {
  group('gerarCsvRelatorioImportacao', () {
    test('gera cabeçalho fixo + uma linha por ImportRow, conteúdo determinístico', () {
      final linhas = [
        ImportReportLinha.fromImportRow(
          _linha(numeroLinha: 2, numeroPatrimonio: '123', sucesso: true, patrimonioId: 'pat-1'),
        ),
        ImportReportLinha.fromImportRow(
          _linha(numeroLinha: 3, numeroPatrimonio: '124', sucesso: false, mensagemErro: 'Já existe'),
        ),
      ];

      final bytes1 = gerarCsvRelatorioImportacao(linhas);
      final bytes2 = gerarCsvRelatorioImportacao(linhas);
      expect(bytes1, equals(bytes2)); // determinístico.

      final texto = utf8.decode(bytes1);
      final ls = texto.split('\r\n');
      expect(ls.first, 'Linha,Número de patrimônio,Status,Id gerado,Mensagem de erro');
      expect(ls[1], '2,123,Sucesso,pat-1,');
      expect(ls[2], '3,124,Erro,,Já existe');
    });

    test('lista vazia gera só o cabeçalho', () {
      final bytes = gerarCsvRelatorioImportacao(const []);
      final texto = utf8.decode(bytes);
      expect(texto.trim(), 'Linha,Número de patrimônio,Status,Id gerado,Mensagem de erro');
    });

    test('campo com vírgula é escapado corretamente (CSV válido)', () {
      final linhas = [
        ImportReportLinha.fromImportRow(
          _linha(numeroLinha: 5, numeroPatrimonio: '500', sucesso: false, mensagemErro: 'Erro, com vírgula'),
        ),
      ];
      final texto = utf8.decode(gerarCsvRelatorioImportacao(linhas));
      expect(texto, contains('"Erro, com vírgula"'));
    });
  });

  group('ImportReportPersistencia', () {
    test('salvar seguido de carregar devolve o mesmo relatório', () async {
      final persistencia = ImportReportPersistencia('/dados', fileSystem: MemoryFileSystem());
      final relatorio = ImportReport.fromImportRows(
        loteId: 'lote-1',
        nomeArquivo: 'inventario.csv',
        linhas: [
          _linha(numeroLinha: 2, numeroPatrimonio: '123', sucesso: true, patrimonioId: 'pat-1'),
          _linha(numeroLinha: 3, numeroPatrimonio: '124', sucesso: false, mensagemErro: 'Já existe'),
        ],
      );

      await persistencia.salvar(relatorio);
      final carregado = persistencia.carregar('lote-1');

      expect(carregado, isNotNull);
      expect(carregado!.loteId, 'lote-1');
      expect(carregado.nomeArquivo, 'inventario.csv');
      expect(carregado.linhas, hasLength(2));
      expect(carregado.linhas[0].numeroPatrimonio, '123');
      expect(carregado.linhas[0].sucesso, isTrue);
      expect(carregado.linhas[1].mensagemErro, 'Já existe');
    });

    test('carregar sem relatório salvo devolve null', () async {
      final persistencia = ImportReportPersistencia('/dados', fileSystem: MemoryFileSystem());
      expect(persistencia.carregar('lote-inexistente'), isNull);
    });

    test('limpar remove o relatório salvo', () async {
      final persistencia = ImportReportPersistencia('/dados', fileSystem: MemoryFileSystem());
      final relatorio = ImportReport.fromImportRows(loteId: 'lote-2', nomeArquivo: null, linhas: []);
      await persistencia.salvar(relatorio);
      expect(persistencia.carregar('lote-2'), isNotNull);

      await persistencia.limpar('lote-2');
      expect(persistencia.carregar('lote-2'), isNull);
    });
  });
}
