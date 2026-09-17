import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_mapping.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/getec_import_profile.dart';

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
      expect(mapeamento.colunaDe(ImportColumnField.localizacao), 3);
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

  group('GetecImportProfile.ehBaixasLocalizadas (PROMPT 8.12)', () {
    test('"BAIXAS LOCALIZADAS" é reconhecido, com tolerância a caixa/espaços', () {
      expect(GetecImportProfile.ehBaixasLocalizadas('BAIXAS LOCALIZADAS'), isTrue);
      expect(GetecImportProfile.ehBaixasLocalizadas('  baixas   localizadas  '), isTrue);
    });
    test('localização comum não é confundida com "BAIXAS LOCALIZADAS"', () {
      expect(GetecImportProfile.ehBaixasLocalizadas('GETEC - UNIVERSITÁRIO'), isFalse);
      expect(GetecImportProfile.ehBaixasLocalizadas('HOME OFFICE'), isFalse);
    });
    test('os outros 2 valores sem localização conhecida não são "BAIXAS LOCALIZADAS"', () {
      expect(GetecImportProfile.ehBaixasLocalizadas('INTANGÍVEIS'), isFalse);
      expect(GetecImportProfile.ehBaixasLocalizadas('TI - SOFTWARE'), isFalse);
    });
  });

  group('GetecImportProfile.mesclarObservacaoComRecuperacaoBaixasLocalizadas (PROMPT 8.12)', () {
    test('não era BAIXAS LOCALIZADAS: observação não muda', () {
      expect(
        GetecImportProfile.mesclarObservacaoComRecuperacaoBaixasLocalizadas(
          observacaoBase: 'Nota qualquer',
          eraBaixasLocalizadas: false,
        ),
        'Nota qualquer',
      );
      expect(
        GetecImportProfile.mesclarObservacaoComRecuperacaoBaixasLocalizadas(
          observacaoBase: null,
          eraBaixasLocalizadas: false,
        ),
        isNull,
      );
    });

    test('era BAIXAS LOCALIZADAS, sem observação prévia: cria a nota', () {
      final resultado = GetecImportProfile.mesclarObservacaoComRecuperacaoBaixasLocalizadas(
        observacaoBase: null,
        eraBaixasLocalizadas: true,
      );
      expect(resultado, contains('retornado à GETEC'));
    });

    test('era BAIXAS LOCALIZADAS, com observação prévia: combina sem substituir', () {
      final resultado = GetecImportProfile.mesclarObservacaoComRecuperacaoBaixasLocalizadas(
        observacaoBase: 'Tombamento anterior: 0008593',
        eraBaixasLocalizadas: true,
      );
      expect(resultado, contains('Tombamento anterior: 0008593'));
      expect(resultado, contains('retornado à GETEC'));
    });

    test('chamado duas vezes seguidas (reanálise) não duplica a nota', () {
      final primeira = GetecImportProfile.mesclarObservacaoComRecuperacaoBaixasLocalizadas(
        observacaoBase: null,
        eraBaixasLocalizadas: true,
      );
      final segunda = GetecImportProfile.mesclarObservacaoComRecuperacaoBaixasLocalizadas(
        observacaoBase: primeira,
        eraBaixasLocalizadas: true,
      );
      expect(segunda, primeira);
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

  group('GetecImportProfile.resolverLocalizacao / localizacaoResolvida', () {
    final localizacoesDaGerencia = [
      Localizacao(id: 'loc-1', setorId: 'setor-getec', nome: 'Home Office', sigla: 'HO', ativo: true, criadoEm: DateTime(2026, 1, 1)),
    ];

    test('resolve por nome exato (case/acento-insensível)', () {
      final resolvida = GetecImportProfile.resolverLocalizacao('home office', localizacoesDaGerencia);
      expect(resolvida?.id, 'loc-1');
    });

    test('resolve por sigla', () {
      final resolvida = GetecImportProfile.resolverLocalizacao('HO', localizacoesDaGerencia);
      expect(resolvida?.id, 'loc-1');
    });

    test('true quando o texto bate exatamente com uma localização ativa', () {
      expect(
        GetecImportProfile.localizacaoResolvida('Home Office', localizacoesDaGerencia, const {}, const {}),
        isTrue,
      );
    });

    test('true quando já existe um mapeamento manual escolhido', () {
      expect(
        GetecImportProfile.localizacaoResolvida(
          'GETEC - UNIVERSITÁRIO',
          localizacoesDaGerencia,
          const {'getec - universitario': 'loc-1'},
          const {},
        ),
        isTrue,
      );
    });

    test('true quando o usuário decidiu explicitamente importar sem localização', () {
      expect(
        GetecImportProfile.localizacaoResolvida(
          'INTANGÍVEIS',
          localizacoesDaGerencia,
          const {},
          const {'intangiveis'},
        ),
        isTrue,
      );
    });

    test('false quando não bate com nada e não há decisão alguma', () {
      expect(
        GetecImportProfile.localizacaoResolvida('LOCAL DESCONHECIDO', localizacoesDaGerencia, const {}, const {}),
        isFalse,
      );
    });
  });

  group('GetecImportProfile — mapeamento oficial de localizações (PROMPT 8.9)', () {
    // Localizações ATIVAS carregadas do Supabase, cobrindo os 15 nomes
    // oficiais conhecidos, exceto "GETEC - CANIDÉ" — deliberadamente
    // ausente para testar o cenário "nome oficial conhecido, mas não
    // cadastrado/ativo no banco" (teste 9).
    final localizacoesCarregadas = [
      for (final entry in {
        'loc-universitario': 'GETEC - Universitário',
        'loc-sede-piso-1': 'Sede - Parque Amazônia - Piso I',
        'loc-home-office': 'Home Office',
        'loc-rack-piso-2': 'Parque Amazônia - Rack Piso II',
        'loc-pplt': 'GETEC-PPLT',
        'loc-datacenter': 'Datacenter - Universitário',
        'loc-rack-gabinete': 'Parque Amazônia - Rack Gabinete',
        'loc-situacao-pa': 'Situação/Situada - PA',
        'loc-sede-piso-2': 'Sede - Parque Amazônia Piso II',
        'loc-lobo-guara': 'GETEC - Lobo Guara',
        'loc-coruja-suindara': 'GETEC - Coruja Suindara',
        'loc-onca-pintada': 'GETEC - Onça Pintada',
        'loc-inserviveis': 'Sala dos Inservíveis',
        'loc-semad': 'SEMAD - Universitário',
      }.entries)
        Localizacao(
          id: entry.key,
          setorId: 'setor-getec',
          nome: entry.value,
          ativo: true,
          criadoEm: DateTime(2026, 1, 1),
        ),
    ];

    test('1. "GETEC - UNIVERSITÁRIO" resolve normalmente', () {
      final resolvida = GetecImportProfile.resolverLocalizacao('GETEC - UNIVERSITÁRIO', localizacoesCarregadas);
      expect(resolvida?.id, 'loc-universitario');
    });

    test('2. "SITUAÇÃO - PA" (forma antiga da planilha) resolve para "SITUAÇÃO/SITUADA - PA"', () {
      expect(GetecImportProfile.nomeOficialConhecido('SITUAÇÃO - PA'), 'SITUAÇÃO/SITUADA - PA');

      final resolvida = GetecImportProfile.resolverLocalizacao('SITUAÇÃO - PA', localizacoesCarregadas);
      expect(resolvida?.id, 'loc-situacao-pa');
      expect(resolvida?.nome, 'Situação/Situada - PA');
    });

    test('3. comparação aceita diferenças de caixa e espaços externos', () {
      final resolvida = GetecImportProfile.resolverLocalizacao(
        '  getec - universitário  ',
        localizacoesCarregadas,
      );
      expect(resolvida?.id, 'loc-universitario');

      expect(GetecImportProfile.nomeOficialConhecido('  situação - pa  '), 'SITUAÇÃO/SITUADA - PA');
      expect(GetecImportProfile.ehValorSemLocalizacaoConhecido('  intangíveis  '), isTrue);
    });

    test('4. "INTANGÍVEIS" é reconhecido como ausência intencional de localização', () {
      expect(GetecImportProfile.ehValorSemLocalizacaoConhecido('INTANGÍVEIS'), isTrue);
      // não é, ao mesmo tempo, um nome oficial de localização física.
      expect(GetecImportProfile.nomeOficialConhecido('INTANGÍVEIS'), isNull);
    });

    test('5. "TI - SOFTWARE" é reconhecido como ausência intencional de localização', () {
      expect(GetecImportProfile.ehValorSemLocalizacaoConhecido('TI - SOFTWARE'), isTrue);
    });

    test('6. "BAIXAS LOCALIZADAS" é reconhecido como ausência intencional de localização', () {
      expect(GetecImportProfile.ehValorSemLocalizacaoConhecido('BAIXAS LOCALIZADAS'), isTrue);
    });

    test('8. valor completamente desconhecido não é nem regra conhecida nem localização oficial', () {
      expect(GetecImportProfile.ehValorSemLocalizacaoConhecido('SETOR MISTERIOSO XPTO'), isFalse);
      expect(GetecImportProfile.nomeOficialConhecido('SETOR MISTERIOSO XPTO'), isNull);
      expect(GetecImportProfile.resolverLocalizacao('SETOR MISTERIOSO XPTO', localizacoesCarregadas), isNull);
    });

    test('9. nome oficial conhecido ("GETEC - CANIDÉ") mas ausente na lista carregada não resolve', () {
      // "GETEC - CANIDÉ" é um dos 15 nomes oficiais, mas foi deliberadamente
      // omitido de localizacoesCarregadas acima — resolverLocalizacao deve
      // retornar null (o controller é quem transforma isso em erro
      // explícito, nunca em null silencioso — ver patrimonio_import_controller_test.dart).
      expect(GetecImportProfile.nomeOficialConhecido('GETEC - CANIDÉ'), 'GETEC - CANIDÉ');
      expect(GetecImportProfile.resolverLocalizacao('GETEC - CANIDÉ', localizacoesCarregadas), isNull);
    });

    test('10. nunca depende de UUID hardcoded — sem localizações carregadas, nada resolve', () {
      // Mesmo para um nome oficial válido, sem a lista carregada do
      // Supabase não há UUID nenhum embutido no código para recorrer.
      expect(GetecImportProfile.resolverLocalizacao('GETEC - UNIVERSITÁRIO', const []), isNull);
      expect(GetecImportProfile.resolverLocalizacao('HOME OFFICE', const []), isNull);
    });
  });

  group('GetecImportProfile.prepararLinhas', () {
    test('aplica a regra do "10" em uma passagem, sem tocar a coluna de localização', () {
      final mapeamento = ImportColumnMapping.vazio
          .definindo(ImportColumnField.numeroPatrimonio, 0)
          .definindo(ImportColumnField.tombamentoAnterior, 1)
          .definindo(ImportColumnField.numeroSerie, 2)
          .definindo(ImportColumnField.localizacao, 3);

      final linhas = [
        ['tombamento', 'tomb_anterior', 'n. serie', 'localizacao'],
        ['1', '10', '10', 'GETEC - UNIVERSITARIO'],
        ['2', '0008593', 'SN123', 'BAIXAS LOCALIZADAS'],
      ];

      final preparo = GetecImportProfile.prepararLinhas(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: mapeamento,
      );

      // cabeçalho preservado sem alteração
      expect(preparo.linhas[0], linhas[0]);

      // linha 1 (índice 1 = linha de arquivo nº 2): "10" virou null nos dois
      // campos com sentinela; localização não é tocada por esta função.
      expect(preparo.linhas[1][1], isNull);
      expect(preparo.linhas[1][2], isNull);
      expect(preparo.linhas[1][3], 'GETEC - UNIVERSITARIO');

      // linha 2 (índice 2 = linha de arquivo nº 3): tombamento anterior real
      // preservado; "BAIXAS LOCALIZADAS" NÃO é mais sinalizada aqui como
      // possível baixa (PROMPT 8.12) — a coluna de localização segue intocada.
      expect(preparo.linhas[2][1], '0008593');
      expect(preparo.linhas[2][3], 'BAIXAS LOCALIZADAS');
    });
  });
}
