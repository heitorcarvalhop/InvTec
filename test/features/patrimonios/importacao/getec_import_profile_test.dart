import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_mapping.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/getec_import_profile.dart';
import 'package:invtec/features/setores/domain/setor.dart';

void main() {
  group('GetecImportProfile.detectar', () {
    test('reconhece os cabeçalhos reais da planilha GETEC, em qualquer ordem', () {
      const cabecalho = ['tombamento', 'tomb_anterior', 'descricao', 'localizacao', 'marca', 'n. serie'];
      expect(GetecImportProfile.detectar(cabecalho), isTrue);
    });

    test('não depende do nome da aba — só do conjunto de cabeçalhos', () {
      const cabecalho = ['Tombamento', 'Tomb_Anterior', 'Descricao', 'Localizacao', 'Marca', 'N. Serie'];
      expect(GetecImportProfile.detectar(cabecalho), isTrue);
    });

    test('planilha genérica (sem "tombamento") não é reconhecida como GETEC', () {
      const cabecalho = ['Patrimônio', 'Tipo', 'Marca', 'Serial', 'Setor'];
      expect(GetecImportProfile.detectar(cabecalho), isFalse);
    });

    test('planilha só com "descrição"/"marca" (colunas genéricas) não basta para reconhecer', () {
      const cabecalho = ['Número', 'Descrição', 'Marca'];
      expect(GetecImportProfile.detectar(cabecalho), isFalse);
    });
  });

  group('GetecImportProfile.mapeamentoSugerido', () {
    test('mapeia as 6 colunas conhecidas pelos índices corretos', () {
      const cabecalho = ['tombamento', 'tomb_anterior', 'descricao', 'localizacao', 'marca', 'n. serie'];
      final mapeamento = GetecImportProfile.mapeamentoSugerido(cabecalho);

      expect(mapeamento.colunaDe(ImportColumnField.numeroPatrimonio), 0);
      expect(mapeamento.colunaDe(ImportColumnField.tombamentoAnterior), 1);
      expect(mapeamento.colunaDe(ImportColumnField.descricao), 2);
      expect(mapeamento.colunaDe(ImportColumnField.setor), 3);
      expect(mapeamento.colunaDe(ImportColumnField.marca), 4);
      expect(mapeamento.colunaDe(ImportColumnField.numeroSerie), 5);
    });
  });

  group('GetecImportProfile.limparSentinela10', () {
    test('texto "10" vira null', () => expect(GetecImportProfile.limparSentinela10('10'), isNull));
    test('texto " 10 " (com espaços) vira null', () => expect(GetecImportProfile.limparSentinela10(' 10 '), isNull));
    test('número inteiro 10 vira null', () => expect(GetecImportProfile.limparSentinela10(10), isNull));
    test('número double 10.0 vira null', () => expect(GetecImportProfile.limparSentinela10(10.0), isNull));
    test('null continua null', () => expect(GetecImportProfile.limparSentinela10(null), isNull));
    test('outro valor não é alterado', () {
      expect(GetecImportProfile.limparSentinela10('AB123'), 'AB123');
      expect(GetecImportProfile.limparSentinela10(100), 100);
    });
  });

  group('GetecImportProfile.indicaBaixa', () {
    test('"BAIXAS LOCALIZADAS" indica baixa', () {
      expect(GetecImportProfile.indicaBaixa('BAIXAS LOCALIZADAS'), isTrue);
    });
    test('localização comum não indica baixa', () {
      expect(GetecImportProfile.indicaBaixa('GETEC - UNIVERSITÁRIO'), isFalse);
      expect(GetecImportProfile.indicaBaixa('HOME OFFICE'), isFalse);
    });
  });

  group('GetecImportProfile.mesclarObservacaoComTombamentoAnterior', () {
    test('sem tombamento anterior, observação não muda', () {
      expect(
        GetecImportProfile.mesclarObservacaoComTombamentoAnterior(
          observacaoBase: 'Nota qualquer',
          tombamentoAnteriorTexto: null,
        ),
        'Nota qualquer',
      );
    });

    test('sem observação prévia, gera só a anotação', () {
      expect(
        GetecImportProfile.mesclarObservacaoComTombamentoAnterior(
          observacaoBase: null,
          tombamentoAnteriorTexto: '0008593',
        ),
        'Tombamento anterior: 0008593',
      );
    });

    test('combina de forma legível com observação já existente', () {
      expect(
        GetecImportProfile.mesclarObservacaoComTombamentoAnterior(
          observacaoBase: 'Importado da base patrimonial GETEC.',
          tombamentoAnteriorTexto: '0008593',
        ),
        'Importado da base patrimonial GETEC.\nTombamento anterior: 0008593',
      );
    });

    test('não duplica a mesma anotação se ela já estiver presente', () {
      const base = 'Importado da base patrimonial GETEC.\nTombamento anterior: 0008593';
      expect(
        GetecImportProfile.mesclarObservacaoComTombamentoAnterior(
          observacaoBase: base,
          tombamentoAnteriorTexto: '0008593',
        ),
        base,
      );
    });
  });

  group('GetecImportProfile.localizacoesUnicas', () {
    test('agrupa localizações únicas com contagem, ignorando célula vazia', () {
      final linhas = [
        ['tombamento', 'localizacao'],
        ['1', 'GETEC - UNIVERSITÁRIO'],
        ['2', 'GETEC - UNIVERSITÁRIO'],
        ['3', 'HOME OFFICE'],
        ['4', ''],
        ['5', null],
      ];

      final resultado = GetecImportProfile.localizacoesUnicas(
        linhas: linhas,
        indiceCabecalho: 0,
        colunaLocalizacao: 1,
      );

      expect(resultado, hasLength(2));
      expect(resultado.first.texto, 'GETEC - UNIVERSITÁRIO');
      expect(resultado.first.contagem, 2);
      expect(resultado.last.texto, 'HOME OFFICE');
      expect(resultado.last.contagem, 1);
    });
  });

  group('GetecImportProfile.localizacaoResolvida', () {
    final setores = [
      Setor(id: 's1', nome: 'GETEC', sigla: 'GE', ativo: true, criadoEm: DateTime(2026, 1, 1)),
    ];

    test('true quando o texto bate exatamente com um setor ativo', () {
      expect(GetecImportProfile.localizacaoResolvida('GETEC', setores, const {}), isTrue);
    });

    test('true quando já existe um mapeamento manual escolhido', () {
      expect(
        GetecImportProfile.localizacaoResolvida('GETEC - UNIVERSITÁRIO', setores, const {
          'getec - universitario': 'GETEC',
        }),
        isTrue,
      );
    });

    test('false quando não bate com nada e não há mapeamento manual', () {
      expect(GetecImportProfile.localizacaoResolvida('SETOR DESCONHECIDO', setores, const {}), isFalse);
    });
  });

  group('GetecImportProfile.prepararLinhas', () {
    test('aplica a regra do "10", o mapeamento de localização e sinaliza baixas — em uma passagem', () {
      final mapeamento = ImportColumnMapping.vazio
          .definindo(ImportColumnField.numeroPatrimonio, 0)
          .definindo(ImportColumnField.tombamentoAnterior, 1)
          .definindo(ImportColumnField.numeroSerie, 2)
          .definindo(ImportColumnField.setor, 3);

      final linhas = [
        ['tombamento', 'tomb_anterior', 'n. serie', 'localizacao'],
        ['1', '10', '10', 'GETEC - UNIVERSITARIO'],
        ['2', '0008593', 'SN123', 'BAIXAS LOCALIZADAS'],
      ];

      final preparo = GetecImportProfile.prepararLinhas(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: mapeamento,
        mapeamentoLocalizacoes: const {'getec - universitario': 'GETEC'},
      );

      // cabeçalho preservado sem alteração
      expect(preparo.linhas[0], linhas[0]);

      // linha 1 (índice 1 = linha de arquivo nº 2): "10" virou null nos dois
      // campos com sentinela, e a localização foi substituída pelo setor.
      expect(preparo.linhas[1][1], isNull);
      expect(preparo.linhas[1][2], isNull);
      expect(preparo.linhas[1][3], 'GETEC');

      // linha 2 (índice 2 = linha de arquivo nº 3): tombamento anterior real
      // preservado, localização sem mapeamento manual permanece como estava,
      // e foi sinalizada como possível baixa pelo número de linha absoluto.
      expect(preparo.linhas[2][1], '0008593');
      expect(preparo.linhas[2][3], 'BAIXAS LOCALIZADAS');
      expect(preparo.linhasComPossivelBaixa, {3});
    });
  });
}
