import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_csv_parser.dart';

const _cabecalho =
    'ID patrimônio no InvTec;Tombamento oficial (texto);Tombamento atual no InvTec;Descrição oficial;'
    'Setor atual (InvTec);Unidade correta (sigla);Unidade correta (nome);Localização atual no InvTec;'
    'Localização na planilha;Localização planejada;Série InvTec;Série oficial;'
    'Tombamento anterior planilha;Status tombamento anterior;Status cruzamento;Status da revisão;'
    'Observação / justificativa';

void main() {
  group('RetificacaoCsvParser', () {
    test('decodifica uma linha real do plano, preservando zeros à esquerda', () {
      const csv =
          '$_cabecalho\n'
          'c710fb70-3bef-48b2-9f63-8cfb048f83ea;003636982;3636982;MONITOR MN801;GETEC;CIMEHGO;'
          'CENTRO DE INFORMAÇÕES METEOROLÓGICAS E HIDROLÓGICAS DE GOIÁS;GETEC - UNIVERSITÁRIO;'
          'SALA DE SITUAÇÃO CEMHG;SALA DE SITUAÇÃO CEMHG;1MN249J20200122;1MN249J20200122;;'
          'SEM_TOMBAMENTO_ANTERIOR;CADASTRADO_COM_DIVERGENCIA;PENDENTE;\n';

      final linhas = RetificacaoCsvParser.parse(csv);

      expect(linhas, hasLength(1));
      final linha = linhas.single;
      expect(linha.numeroLinha, 2);
      expect(linha.patrimonioId, 'c710fb70-3bef-48b2-9f63-8cfb048f83ea');
      // zeros à esquerda preservados — nunca convertido para número.
      expect(linha.tombamentoOficial, '003636982');
      expect(linha.tombamentoAtualInvtec, '3636982');
      expect(linha.setorAtualTexto, 'GETEC');
      expect(linha.unidadeCorretaSigla, 'CIMEHGO');
      expect(
        linha.unidadeCorretaNome,
        'CENTRO DE INFORMAÇÕES METEOROLÓGICAS E HIDROLÓGICAS DE GOIÁS',
      );
      expect(linha.localizacaoAtualTexto, 'GETEC - UNIVERSITÁRIO');
      expect(linha.localizacaoPlanejadaTexto, 'SALA DE SITUAÇÃO CEMHG');
      expect(linha.tombamentoAnteriorPlanilha, isNull); // célula vazia -> null
      expect(linha.observacao, isNull);
    });

    test('decodifica várias linhas em ordem, numerando a partir de 2', () {
      const csv =
          '$_cabecalho\n'
          'id-1;001;1;Desc 1;GETEC;AAA;Unidade AAA;;;;;;;;;;\n'
          'id-2;002;2;Desc 2;GETEC;BBB;Unidade BBB;;;;;;;;;;\n';

      final linhas = RetificacaoCsvParser.parse(csv);

      expect(linhas, hasLength(2));
      expect(linhas[0].numeroLinha, 2);
      expect(linhas[0].patrimonioId, 'id-1');
      expect(linhas[1].numeroLinha, 3);
      expect(linhas[1].patrimonioId, 'id-2');
    });

    test('cabeçalho diferente do esperado: lança, nunca tenta adivinhar colunas', () {
      const csv = 'Coluna errada;Outra coluna\nvalor1;valor2\n';

      expect(
        () => RetificacaoCsvParser.parse(csv),
        throwsA(isA<RetificacaoCsvFormatoInvalidoException>()),
      );
    });

    test('linha com número de colunas diferente do cabeçalho: lança', () {
      const csv = '$_cabecalho\nid-1;001;1;Desc;GETEC;AAA\n'; // faltam colunas

      expect(
        () => RetificacaoCsvParser.parse(csv),
        throwsA(isA<RetificacaoCsvFormatoInvalidoException>()),
      );
    });

    test('ID patrimônio vazio: lança (nunca produz uma linha sem identidade)', () {
      const csv = '$_cabecalho\n;001;1;Desc;GETEC;AAA;Unidade AAA;;;;;;;;;;\n';

      expect(
        () => RetificacaoCsvParser.parse(csv),
        throwsA(isA<RetificacaoCsvFormatoInvalidoException>()),
      );
    });

    test('arquivo vazio: lança', () {
      expect(
        () => RetificacaoCsvParser.parse(''),
        throwsA(isA<RetificacaoCsvFormatoInvalidoException>()),
      );
    });
  });
}
