import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/data/sei_despacho_parser.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';

import 'sei_pdf_fixture_texto.dart';

/// PROMPT 11.1, seções 7/8/30: valida o parser determinístico contra o
/// CONTEÚDO real do PDF de referência (`SEI_95955192_Despacho_577.pdf`) —
/// o binário não é versionado (documento institucional), mas o texto
/// reproduzido em `sei_pdf_fixture_texto.dart` é fiel ao que foi extraído
/// dele, imperfeições incluídas (seção 9). Nenhum teste chama Supabase nem
/// produção — é só texto → modelo, puro.
void main() {
  group('PROMPT 11.1 — SeiDeterministicParser com o documento SEI real de referência', () {
    late SeiDocumentoExtraido documento;

    setUpAll(() async {
      documento = await const SeiDeterministicParser().analisar(
        nomeArquivo: 'SEI_95955192_Despacho_577.pdf',
        tamanhoBytes: 60000,
        hashSha256: 'hash-de-teste',
        textoPorPagina: seiFixtureTextoPorPagina,
      );
    });

    test('metadados do documento', () {
      expect(documento.numeroProcesso, '202600017000011');
      expect(documento.numeroDocumentoSei, '95955192');
      expect(documento.tipoDocumento, SeiTipoDocumento.despacho);
      expect(documento.numeroDocumentoFormatado, '577/2026/SEMAD/GETEC-12014');
      expect(documento.assunto, 'Transferência de patrimônio');
      expect(documento.tipoMovimentacaoInferido, MovimentacaoTipo.transferencia);
      expect(documento.signatario, contains('LAERCIO'));
    });

    test('encontra exatamente 33 itens', () {
      expect(documento.itens, hasLength(33));
    });

    test('encontra exatamente 33 números de patrimônio distintos', () {
      final numeros = documento.itens.map((i) => i.numeroPatrimonio).whereType<String>().toSet();
      expect(numeros, hasLength(33));
    });

    test('nenhum item ficou sem número de patrimônio identificado', () {
      for (final item in documento.itens) {
        expect(item.numeroPatrimonio, isNotNull, reason: 'linha ${item.linha}');
        expect(item.numeroPatrimonio, hasLength(7), reason: 'linha ${item.linha}');
      }
    });

    test('item 4157090: destino GEASI, chamado 4556, equipamento Monitor Positivo', () {
      final item = documento.itens.firstWhere((i) => i.numeroPatrimonio == '4157090');
      expect(item.equipamento, 'Monitor Positivo');
      expect(item.unidadeOrigemTexto, contains('GETEC'));
      expect(item.unidadeDestinoTexto, contains('GEASI'));
      expect(item.numeroChamado, '4556');
      expect(item.confiancaPatrimonio, SeiConfianca.alta);
    });

    test('item 3452536: destino GESOL, chamado 4496, equipamento Notebook Dell', () {
      final item = documento.itens.firstWhere((i) => i.numeroPatrimonio == '3452536');
      expect(item.equipamento, 'Notebook Dell');
      expect(item.unidadeDestinoTexto, contains('GESOL'));
      expect(item.numeroChamado, '4496');
    });

    test('item 3636975: destino CIMEHGO, chamado 4429, equipamento Monitor Multi', () {
      final item = documento.itens.firstWhere((i) => i.numeroPatrimonio == '3636975');
      expect(item.equipamento, 'Monitor Multi');
      expect(item.unidadeDestinoTexto, contains('CIMEHGO'));
      expect(item.numeroChamado, '4429');
    });

    test(
      'os 6 itens "Estabilizador" reconstroem o número mesmo com dígito intercalado no texto extraído',
      () {
        const numerosEsperados = ['3152941', '3120388', '3163983', '3170562', '3152919', '3152959'];
        for (final numero in numerosEsperados) {
          final item = documento.itens.firstWhere(
            (i) => i.numeroPatrimonio == numero,
            orElse: () => throw StateError('patrimônio $numero não encontrado'),
          );
          expect(item.equipamento, 'Estabilizador', reason: numero);
          expect(item.confiancaPatrimonio, SeiConfianca.media, reason: 'reconstruído a partir de texto intercalado');
          expect(item.observacoesParsing, isNotEmpty);
        }
      },
    );

    test('31 dos 33 itens têm destino GEASI (os outros 2 são GESOL e CIMEHGO)', () {
      final destinoGeasi = documento.itens.where((i) => i.unidadeDestinoTexto?.contains('GEASI') ?? false);
      expect(destinoGeasi.length, 31);
    });

    test('todas as páginas (1 a 4) têm pelo menos um item cuja paginaOrigem aponta para elas', () {
      final paginas = documento.itens.map((i) => i.paginaOrigem).toSet();
      expect(paginas, containsAll([1, 2, 3, 4]));
    });
  });

  group('PROMPT 11.1.1 — robustez do parser (documentos sintéticos)', () {
    test('equipamento fora do vocabulário conhecido ainda localiza a tabela e o item', () async {
      final documento = await const SeiDeterministicParser().analisar(
        nomeArquivo: 'sintetico.pdf',
        tamanhoBytes: 1000,
        hashSha256: 'hash',
        textoPorPagina: [_paginaSintetica('Purificador\nAgua\n1234567\n')],
      );

      expect(documento.itens, hasLength(1));
      final item = documento.itens.single;
      expect(item.equipamento, contains('Purificador'));
      expect(item.numeroPatrimonio, '1234567');
      expect(item.confiancaPatrimonio, SeiConfianca.alta);
    });

    test('candidato de patrimônio com comprimento atípico (6 dígitos) ainda é extraído, com confiança baixa', () async {
      final documento = await const SeiDeterministicParser().analisar(
        nomeArquivo: 'sintetico.pdf',
        tamanhoBytes: 1000,
        hashSha256: 'hash',
        textoPorPagina: [_paginaSintetica('Monitor\nPositivo\n123456\n')],
      );

      final item = documento.itens.single;
      expect(item.numeroPatrimonio, '123456');
      expect(item.confiancaPatrimonio, SeiConfianca.baixa);
      expect(item.observacoesParsing, isNotEmpty);
    });

    test('um número de processo SEI (15 dígitos) próximo da linha não vira número de patrimônio', () async {
      final documento = await const SeiDeterministicParser().analisar(
        nomeArquivo: 'sintetico.pdf',
        tamanhoBytes: 1000,
        hashSha256: 'hash',
        textoPorPagina: [_paginaSintetica('Monitor\n(vide processo 202600017000011)\n4157090\n')],
      );

      final item = documento.itens.single;
      expect(item.numeroPatrimonio, '4157090');
      expect(item.numeroPatrimonio, isNot('202600017000011'));
    });

    test('um número de documento SEI (8 dígitos) próximo da linha não vira número de patrimônio', () async {
      final documento = await const SeiDeterministicParser().analisar(
        nomeArquivo: 'sintetico.pdf',
        tamanhoBytes: 1000,
        hashSha256: 'hash',
        textoPorPagina: [_paginaSintetica('Notebook\n(SEI 95955192)\n3452536\n')],
      );

      final item = documento.itens.single;
      expect(item.numeroPatrimonio, '3452536');
      expect(item.numeroPatrimonio, isNot('95955192'));
    });

    test('um número de chamado (4 dígitos) próximo da linha não vira número de patrimônio', () async {
      final documento = await const SeiDeterministicParser().analisar(
        nomeArquivo: 'sintetico.pdf',
        tamanhoBytes: 1000,
        hashSha256: 'hash',
        textoPorPagina: [_paginaSintetica('Desktop\n(chamado 4556)\n4155322\n')],
      );

      final item = documento.itens.single;
      expect(item.numeroPatrimonio, '4155322');
      expect(item.numeroPatrimonio, isNot('4556'));
    });
  });
}

/// Documento sintético mínimo (cabeçalho + UM item) usado pelos testes de
/// robustez do PROMPT 11.1.1 — reproduz só a estrutura necessária para
/// exercitar [SeiDeterministicParser] isoladamente, sem depender do PDF
/// real de referência. [zonaEquipPatrimonio] é o texto bruto que caeria na
/// zona "equipamento+patrimônio" de uma linha (antes da origem).
String _paginaSintetica(String zonaEquipPatrimonio) => '''
ESTADO DE GOIÁS
Referência: Processo nº 202600017000099
Assunto: Transferência de patrimônio
DESPACHO Nº 999/2026/SEMAD/GETEC-99999
Unidade
de Origem
Unidade Destino
Chamado
4Biz/
SEI
$zonaEquipPatrimonio
GETEC -
Gerencia de
Tecnologia
Gerência de
Licenciamento de
Atividades Estratégicas
e de Significativo
Impacto – GEASI
4556
''';
