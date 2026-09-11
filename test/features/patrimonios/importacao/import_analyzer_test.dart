import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_analyzer.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_mapping.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/setores/domain/setor.dart';

final _tipos = [
  TipoPatrimonio(id: 'tipo-notebook', nome: 'Notebook', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  TipoPatrimonio(id: 'tipo-monitor', nome: 'Monitor', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];

final _setores = [
  Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GE', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-almoxarifado', nome: 'Almoxarifado', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];

const _mapeamentoPadrao = ImportColumnMapping({
  ImportColumnField.numeroPatrimonio: 0,
  ImportColumnField.tipo: 1,
  ImportColumnField.marca: 2,
  ImportColumnField.modelo: 3,
  ImportColumnField.numeroSerie: 4,
  ImportColumnField.setor: 5,
  ImportColumnField.responsavel: 6,
});

PatrimonioDetalhe _existente(String numero) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'existing-1',
      numeroPatrimonio: numero,
      tipoId: 'tipo-notebook',
      marca: 'Dell Antigo',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-getec',
      dataCadastro: DateTime(2025, 1, 1),
      atualizadoEm: DateTime(2025, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: 'GETEC',
  );
}

void main() {
  group('ImportAnalyzer.analisar — classificação', () {
    final linhas = <List<Object?>>[
      ['Patrimônio', 'Tipo', 'Marca', 'Modelo', 'Serial', 'Setor', 'Responsável'],
      ['00045872', 'Notebook', 'Dell', 'Latitude 5440', 'AAA111', 'GETEC', 'João'],
      ['00045873', 'Notebok', 'Dell', 'Latitude', 'BBB222', 'GETEC', 'Maria'],
      ['00045874', 'Notebook', 'HP', 'Elite', 'CCC333', 'Marte', 'Carlos'],
      ['99999', 'Monitor', 'LG', '24', null, 'GETEC', null],
      ['99999', 'Monitor', 'LG', '24', null, 'GETEC', null],
      ['00000001', 'Notebook', 'Dell', 'X1', 'SERX', 'GETEC', 'Ana'],
      ['00045890', 'Notebook', 'Dell', 'Y2', 'DBSER1', 'GETEC', 'Bia'],
      ['00045891', 'Notebook', 'Dell', 'Z3', 'SHARED1', 'GETEC', 'Rui'],
      ['00045892', 'Notebook', 'Dell', 'Z4', 'SHARED1', 'GETEC', 'Zoe'],
      [null, null, null, null, null, null, null],
      [null, 'Monitor', 'LG', '27', null, 'GETEC', null],
    ];

    late List<ImportRow> resultado;

    setUpAll(() {
      resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: _mapeamentoPadrao,
        // Origem padrão distinta do destino ('GETEC') usado nas linhas —
        // sem isso, toda linha bateria na regra "origem == destino".
        padroes: ImportDefaults(origemPadraoId: 'setor-almoxarifado'),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: {'00000001': _existente('00000001')},
        numerosSerieExistentesNoBanco: {'DBSER1'},
      );
    });

    test('pula linhas totalmente vazias', () {
      expect(resultado, hasLength(10)); // 11 linhas de dados - 1 vazia
    });

    test('linha pronta: tipo e setor resolvidos, sem número duplicado', () {
      final linha = resultado.firstWhere((l) => l.numeroPatrimonio == '00045872');
      expect(linha.status, ImportRowStatus.pronto);
      expect(linha.tipoIdResolvido, 'tipo-notebook');
      expect(linha.destinoIdResolvido, 'setor-getec');
    });

    test('tipo não encontrado gera erro e sugestão por similaridade', () {
      final linha = resultado.firstWhere((l) => l.numeroPatrimonio == '00045873');
      expect(linha.status, ImportRowStatus.erro);
      expect(linha.tipoIdResolvido, isNull);
      expect(linha.tipoIdSugerido, 'tipo-notebook');
      expect(linha.issues.any((i) => i.message.contains('Tipo não encontrado')), isTrue);
    });

    test('setor não encontrado (sem padrão configurado) gera erro', () {
      final linha = resultado.firstWhere((l) => l.numeroPatrimonio == '00045874');
      expect(linha.status, ImportRowStatus.erro);
      expect(linha.destinoIdResolvido, isNull);
      expect(linha.issues.any((i) => i.message.contains('Setor não encontrado')), isTrue);
    });

    test('número patrimonial duplicado no arquivo bloqueia ambas as linhas', () {
      final duplicadas = resultado.where((l) => l.numeroPatrimonioNormalizado == '99999').toList();
      expect(duplicadas, hasLength(2));
      for (final linha in duplicadas) {
        expect(linha.duplicadoNoArquivo, isTrue);
        expect(linha.status, ImportRowStatus.erro);
      }
    });

    test('número já existente no banco fica como "existente" (não sobrescreve setor/responsável)', () {
      final linha = resultado.firstWhere((l) => l.numeroPatrimonio == '00000001');
      expect(linha.existenteNoBanco, isNotNull);
      expect(linha.status, ImportRowStatus.existente);
    });

    test('atualizar metadados é uma decisão explícita do usuário', () {
      final linha = resultado.firstWhere((l) => l.numeroPatrimonio == '00000001');
      linha.acaoExistente = ImportExistingAction.atualizarMetadados;
      ImportAnalyzer.classificar(linha);
      expect(linha.status, ImportRowStatus.atualizar);
    });

    test('possível duplicidade de série contra o banco gera aviso, não erro', () {
      final linha = resultado.firstWhere((l) => l.numeroPatrimonio == '00045890');
      expect(linha.possivelDuplicidadeSerial, isTrue);
      expect(linha.status, ImportRowStatus.aviso);
    });

    test('possível duplicidade de série dentro do próprio arquivo gera aviso nas duas linhas', () {
      final duplicadas = resultado.where((l) => l.numeroSerie == 'SHARED1').toList();
      expect(duplicadas, hasLength(2));
      for (final linha in duplicadas) {
        expect(linha.possivelDuplicidadeSerial, isTrue);
        expect(linha.status, ImportRowStatus.aviso);
      }
    });

    test('número patrimonial é opcional: linha sem número pode ficar pronta', () {
      final linha = resultado.firstWhere((l) => l.marca == 'LG' && l.modelo == '27');
      expect(linha.numeroPatrimonio, isNull);
      expect(linha.status, ImportRowStatus.pronto);
    });
  });

  group('ImportAnalyzer.analisar — padrões e prioridade linha x padrão', () {
    test('padrão de destino é usado quando a coluna de setor está vazia', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor'],
        ['1', 'Notebook', null],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
        }),
        padroes: ImportDefaults(destinoPadraoId: 'setor-getec', origemPadraoId: 'setor-almoxarifado'),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      expect(resultado.single.destinoIdResolvido, 'setor-getec');
      expect(resultado.single.usouDestinoPadrao, isTrue);
      expect(resultado.single.status, ImportRowStatus.pronto);
    });

    test('valor da linha tem prioridade sobre o padrão', () {
      final outroSetor = Setor(
        id: 'setor-outro',
        nome: 'Outro Setor',
        ativo: true,
        criadoEm: DateTime(2026, 1, 1),
      );
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor'],
        ['1', 'Notebook', 'Outro Setor'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
        }),
        padroes: ImportDefaults(destinoPadraoId: 'setor-getec'),
        tiposAtivos: _tipos,
        setoresAtivos: [..._setores, outroSetor],
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.destinoIdResolvido, 'setor-outro');
      expect(linha.usouDestinoPadrao, isFalse);
    });

    test('tipo vazio é sempre erro, mesmo sem coluna de setor com problema', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor'],
        ['1', null, 'GETEC'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
        }),
        padroes: ImportDefaults(),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      expect(resultado.single.status, ImportRowStatus.erro);
      expect(
        resultado.single.issues.any((i) => i.message.contains('Tipo é obrigatório')),
        isTrue,
      );
    });

    test('data de entrada reconhecida é usada; data padrão só entra se ausente/inválida', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor', 'Data de entrada'],
        ['1', 'Notebook', 'GETEC', '10/03/2024'],
        ['2', 'Notebook', 'GETEC', null],
        ['3', 'Notebook', 'GETEC', 'não é uma data'],
      ];
      final dataPadrao = DateTime(2026, 5, 1);
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
          ImportColumnField.dataEntrada: 3,
        }),
        padroes: ImportDefaults(dataPadrao: dataPadrao, origemPadraoId: 'setor-almoxarifado'),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final comData = resultado.firstWhere((l) => l.numeroPatrimonio == '1');
      expect(comData.dataEntrada, DateTime(2024, 3, 10));
      expect(comData.usouDataPadrao, isFalse);

      final semData = resultado.firstWhere((l) => l.numeroPatrimonio == '2');
      expect(semData.dataEntrada, dataPadrao);
      expect(semData.usouDataPadrao, isTrue);

      final dataInvalida = resultado.firstWhere((l) => l.numeroPatrimonio == '3');
      expect(dataInvalida.dataEntrada, dataPadrao);
      expect(dataInvalida.usouDataPadrao, isTrue);
      expect(dataInvalida.status, ImportRowStatus.aviso);
      expect(
        dataInvalida.issues.any((i) => i.message.contains('Data de entrada não reconhecida')),
        isTrue,
      );
    });

    test('setor de origem desconhecido, sem origem padrão, é erro — nunca fica sem resolução', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor', 'Origem'],
        ['1', 'Notebook', 'GETEC', 'Setor Inexistente XYZ'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
          ImportColumnField.origem: 3,
        }),
        padroes: ImportDefaults(),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.origemIdResolvido, isNull);
      expect(linha.status, ImportRowStatus.erro);
      expect(
        linha.issues.any((i) => i.message.contains('Setor de origem não encontrado')),
        isTrue,
      );
    });

    test('setor de origem desconhecido cai para a origem padrão (aviso, não bloqueia)', () {
      final almoxarifado = Setor(
        id: 'setor-almoxarifado',
        nome: 'Almoxarifado',
        ativo: true,
        criadoEm: DateTime(2026, 1, 1),
      );
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor', 'Origem'],
        ['1', 'Notebook', 'GETEC', 'Setor Inexistente XYZ'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
          ImportColumnField.origem: 3,
        }),
        padroes: ImportDefaults(origemPadraoId: 'setor-almoxarifado'),
        tiposAtivos: _tipos,
        setoresAtivos: [..._setores, almoxarifado],
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.origemIdResolvido, 'setor-almoxarifado');
      expect(linha.usouOrigemPadrao, isTrue);
      expect(linha.status, ImportRowStatus.aviso);
    });

    test('origem ausente e sem origem padrão é erro — origem é obrigatória num patrimônio novo', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor'],
        ['1', 'Notebook', 'GETEC'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
        }),
        padroes: ImportDefaults(),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.origemIdResolvido, isNull);
      expect(linha.status, ImportRowStatus.erro);
      expect(
        linha.issues.any((i) => i.message.contains('Nenhuma origem informada')),
        isTrue,
      );
    });

    test('origem ausente com origem padrão válida fica pronta', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor'],
        ['1', 'Notebook', 'GETEC'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
        }),
        // origem padrão distinta do destino ('GETEC'), para não colidir com
        // a regra "origem e destino precisam ser diferentes".
        padroes: ImportDefaults(origemPadraoId: 'setor-almoxarifado'),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.origemIdResolvido, 'setor-almoxarifado');
      expect(linha.status, ImportRowStatus.pronto);
    });

    test('destino desconhecido cai para o destino padrão (aviso, não bloqueia)', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor'],
        ['1', 'Notebook', 'Setor Inexistente XYZ'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
        }),
        padroes: ImportDefaults(destinoPadraoId: 'setor-getec', origemPadraoId: 'setor-almoxarifado'),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.destinoIdResolvido, 'setor-getec');
      expect(linha.usouDestinoPadrao, isTrue);
      expect(linha.status, ImportRowStatus.aviso);
    });

    test('origem igual ao destino é erro, mesmo quando os dois vêm de padrões diferentes que colidem', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor', 'Origem'],
        ['1', 'Notebook', 'GETEC', 'GETEC'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
          ImportColumnField.origem: 3,
        }),
        padroes: ImportDefaults(),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.status, ImportRowStatus.erro);
      expect(
        linha.issues.any((i) => i.message.contains('origem e o destino precisam ser diferentes')),
        isTrue,
      );
    });

    test('data de entrada não reconhecida sem data padrão é erro', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor', 'Data de entrada'],
        ['1', 'Notebook', 'GETEC', 'não é uma data'],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
          ImportColumnField.dataEntrada: 3,
        }),
        padroes: ImportDefaults(), // sem data padrão configurada
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.dataEntrada, isNull);
      expect(linha.status, ImportRowStatus.erro);
      expect(
        linha.issues.any((i) => i.message.contains('nenhuma data padrão foi configurada')),
        isTrue,
      );
    });

    test('data de entrada ausente (célula vazia) sem padrão não é erro', () {
      final linhas = [
        ['Patrimônio', 'Tipo', 'Setor', 'Data de entrada'],
        ['1', 'Notebook', 'GETEC', null],
      ];
      final resultado = ImportAnalyzer.analisar(
        linhas: linhas,
        indiceCabecalho: 0,
        mapeamento: const ImportColumnMapping({
          ImportColumnField.numeroPatrimonio: 0,
          ImportColumnField.tipo: 1,
          ImportColumnField.setor: 2,
          ImportColumnField.dataEntrada: 3,
        }),
        padroes: ImportDefaults(origemPadraoId: 'setor-almoxarifado'),
        tiposAtivos: _tipos,
        setoresAtivos: _setores,
        existentesPorNumero: const {},
        numerosSerieExistentesNoBanco: const {},
      );

      final linha = resultado.single;
      expect(linha.dataEntrada, isNull);
      expect(linha.status, ImportRowStatus.pronto);
    });
  });

  group('ImportAnalyzer.classificar — decisões manuais reclassificam a linha', () {
    test('ignorar uma linha manualmente sempre resulta em "ignorado"', () {
      final linha = ImportRow(numeroLinha: 2, celulas: {});
      linha.ignoradaManualmente = true;
      ImportAnalyzer.classificar(linha);
      expect(linha.status, ImportRowStatus.ignorado);
    });

    test('resolver tipo manualmente remove o erro e classifica como pronto', () {
      final linha = ImportRow(numeroLinha: 2, celulas: {})
        ..tipoTexto = 'Notebok'
        ..destinoIdResolvido = 'setor-getec'
        ..origemIdResolvido = 'setor-almoxarifado';
      ImportAnalyzer.classificar(linha);
      expect(linha.status, ImportRowStatus.erro);

      linha.tipoIdResolvido = 'tipo-notebook';
      ImportAnalyzer.classificar(linha);
      expect(linha.status, ImportRowStatus.pronto);
    });
  });
}
