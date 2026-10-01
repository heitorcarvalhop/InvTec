import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/domain/patrimonio_comparacao.dart';

/// Testes do motor de comparação PURO
/// ([PatrimonioComparador]), operando diretamente sobre [ImportRow]s
/// montadas à mão (mesmo padrão de [ImportAnalyzer] em
/// `import_analyzer_test.dart`: sem Excel/CSV real, sem repositório, sem
/// rede — só as estruturas que [PatrimonioImportController.compararParaAdmin]
/// já produziria depois de rodar a MESMA análise da importação
/// convencional).
PatrimonioDetalhe _existente({
  String id = 'p-123456',
  String numeroPatrimonio = '123456',
  String? descricao = 'Notebook Dell',
  String? marca = 'DELL',
  String? modelo,
  String? numeroSerie,
  String? observacao,
  String setorAtualId = 'setor-getec',
  String setorNome = 'GETEC',
  String? localizacaoAtualId,
  String? localizacaoNome,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numeroPatrimonio,
      tipoId: 'tipo-notebook',
      descricao: descricao,
      marca: marca,
      modelo: modelo,
      numeroSerie: numeroSerie,
      observacao: observacao,
      status: PatrimonioStatus.emUso,
      setorAtualId: setorAtualId,
      localizacaoAtualId: localizacaoAtualId,
      responsavelAtual: 'João',
      dataCadastro: DateTime(2024, 1, 1),
      atualizadoEm: DateTime(2024, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: setorNome,
    localizacaoNome: localizacaoNome,
  );
}

/// Uma [ImportRow] já "resolvida" como [ImportAnalyzer.analisar] +
/// pós-processamento do perfil deixariam — só os campos que
/// [PatrimonioComparador] efetivamente lê.
ImportRow _linha({
  int numeroLinha = 2,
  Map<ImportColumnField, String?> celulas = const {},
  String? numeroPatrimonio,
  String? descricao,
  String? marca,
  String? modelo,
  String? numeroSerie,
  String? observacao,
  String? setorTexto,
  String? destinoIdResolvido,
  bool usouDestinoPadrao = false,
  String? localizacaoTexto,
  String? localizacaoIdResolvida,
  bool localizacaoPendente = false,
  bool localizacaoOficialAusente = false,
  bool duplicadoNoArquivo = false,
  PatrimonioDetalhe? existenteNoBanco,
  String? tipoIdResolvido = 'tipo-notebook',
}) {
  final linha = ImportRow(numeroLinha: numeroLinha, celulas: celulas)
    ..numeroPatrimonio = numeroPatrimonio
    ..numeroPatrimonioNormalizado = numeroPatrimonio?.trim().toUpperCase()
    ..descricao = descricao
    ..marca = marca
    ..modelo = modelo
    ..numeroSerie = numeroSerie
    ..observacao = observacao
    ..setorTexto = setorTexto
    ..destinoIdResolvido = destinoIdResolvido
    ..usouDestinoPadrao = usouDestinoPadrao
    ..localizacaoTexto = localizacaoTexto
    ..localizacaoIdResolvida = localizacaoIdResolvida
    ..localizacaoPendente = localizacaoPendente
    ..localizacaoOficialAusente = localizacaoOficialAusente
    ..duplicadoNoArquivo = duplicadoNoArquivo
    ..existenteNoBanco = existenteNoBanco
    ..tipoIdResolvido = tipoIdResolvido;
  return linha;
}

void main() {
  group('PatrimonioComparador — CENÁRIO 1: patrimônio idêntico', () {
    test('todos os campos comparáveis batem → IDÊNTICO, sem divergências, retirado da revisão', () {
      final existente = _existente(setorAtualId: 'setor-getec');
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '123456', ImportColumnField.descricao: 'Notebook Dell', ImportColumnField.marca: 'DELL'},
        numeroPatrimonio: '123456',
        descricao: 'Notebook Dell',
        marca: 'DELL',
        existenteNoBanco: existente,
      );

      final lote = PatrimonioComparador.comparar([linha]);

      expect(lote.itens.single.classificacao, ClassificacaoComparacao.identico);
      expect(lote.itens.single.divergencias, isEmpty);
      expect(lote.resumo.identicos, 1);
      expect(lote.resumo.divergentes, 0);
      expect(lote.resumo.totalLinhas, 1);
      // seção 1/5: idêntico some da lista de revisão, mas continua contado.
      expect(lote.itensParaRevisao, isEmpty);
    });
  });

  group('PatrimonioComparador — CENÁRIO 2: localização divergente', () {
    test('só Localização diverge → DIVERGENTE com 1 CampoDivergente do tipo localizacao', () {
      final existente = _existente(localizacaoAtualId: 'loc-universitario', localizacaoNome: 'GETEC - Universitário');
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '123456', ImportColumnField.localizacao: 'GETEC-PPLT'},
        numeroPatrimonio: '123456',
        localizacaoTexto: 'GETEC-PPLT',
        localizacaoIdResolvida: 'loc-pplt',
        existenteNoBanco: existente,
      );

      final lote = PatrimonioComparador.comparar([linha]);
      final item = lote.itens.single;

      expect(item.classificacao, ClassificacaoComparacao.divergente);
      expect(item.divergencias, hasLength(1));
      expect(item.divergencias.single.campo, 'Localização atual');
      expect(item.divergencias.single.tipo, TipoDivergencia.localizacao);
      expect(item.divergencias.single.valorInvtec, 'GETEC - Universitário');
      expect(item.divergencias.single.valorPlanilha, 'GETEC-PPLT');
      expect(lote.resumo.divergenciasPorCampo['Localização atual'], 1);
    });
  });

  group('PatrimonioComparador — CENÁRIO 3: dois ou mais campos divergentes', () {
    test('Marca E Setor divergem no mesmo patrimônio → 1 patrimônio divergente, 2 CampoDivergente, sem contar em dobro', () {
      final existente = _existente(marca: 'DELL', setorAtualId: 'setor-getec');
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '123456', ImportColumnField.marca: 'LENOVO', ImportColumnField.setor: 'TI'},
        numeroPatrimonio: '123456',
        marca: 'LENOVO',
        setorTexto: 'TI',
        destinoIdResolvido: 'setor-ti',
        existenteNoBanco: existente,
      );

      final lote = PatrimonioComparador.comparar([linha]);
      final item = lote.itens.single;

      expect(item.classificacao, ClassificacaoComparacao.divergente);
      expect(item.divergencias, hasLength(2));
      expect(item.divergencias.map((d) => d.campo), containsAll(['Marca', 'Setor atual']));
      // um patrimônio com várias divergências soma 1 (nunca 2) em `divergentes`.
      expect(lote.resumo.divergentes, 1);
      expect(lote.resumo.totalLinhas, 1);
      expect(lote.resumo.divergenciasPorCampo['Marca'], 1);
      expect(lote.resumo.divergenciasPorCampo['Setor atual'], 1);
    });
  });

  group('PatrimonioComparador — CENÁRIO 4: patrimônio novo', () {
    test('número inexistente no banco e sem erro de análise → NOVO', () {
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '999999', ImportColumnField.descricao: 'Monitor LG'},
        numeroPatrimonio: '999999',
        descricao: 'Monitor LG',
        existenteNoBanco: null,
      );

      final lote = PatrimonioComparador.comparar([linha]);

      expect(lote.itens.single.classificacao, ClassificacaoComparacao.novo);
      expect(lote.itens.single.patrimonioId, isNull);
      expect(lote.resumo.novos, 1);
    });

    test('novo com issue de erro (ex.: tipo não encontrado) → BLOQUEADO, não NOVO', () {
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '999999'},
        numeroPatrimonio: '999999',
        existenteNoBanco: null,
        tipoIdResolvido: null,
      )..issues.add(const ImportIssue(ImportIssueSeverity.erro, "Tipo não encontrado: 'Xis'."));

      final lote = PatrimonioComparador.comparar([linha]);

      expect(lote.itens.single.classificacao, ClassificacaoComparacao.bloqueado);
      expect(lote.itens.single.motivoBloqueio, contains('Tipo não encontrado'));
      expect(lote.resumo.bloqueados, 1);
      expect(lote.resumo.novos, 0);
    });
  });

  group('PatrimonioComparador — CENÁRIO 5: tombamento duplicado dentro da própria planilha', () {
    test('ambas as ocorrências ficam BLOQUEADAS, nunca comparadas ao banco', () {
      final linha1 = _linha(numeroLinha: 2, numeroPatrimonio: '111111', duplicadoNoArquivo: true);
      final linha2 = _linha(numeroLinha: 5, numeroPatrimonio: '111111', duplicadoNoArquivo: true);

      final lote = PatrimonioComparador.comparar([linha1, linha2]);

      expect(lote.itens.every((i) => i.classificacao == ClassificacaoComparacao.bloqueado), isTrue);
      expect(lote.itens.every((i) => i.motivoBloqueio!.contains('duplicado')), isTrue);
      expect(lote.resumo.bloqueados, 2);
      expect(lote.resumo.identicos + lote.resumo.divergentes + lote.resumo.novos, 0);
    });
  });

  group('PatrimonioComparador — CENÁRIO 6: localização não identificada', () {
    test('localizacaoPendente=true → BLOQUEADO, nunca escolhido por aproximação', () {
      final linha = _linha(
        numeroPatrimonio: '123456',
        localizacaoTexto: 'SALA MISTERIOSA',
        localizacaoPendente: true,
        existenteNoBanco: _existente(),
      );

      final lote = PatrimonioComparador.comparar([linha]);
      final item = lote.itens.single;

      expect(item.classificacao, ClassificacaoComparacao.bloqueado);
      expect(item.motivoBloqueio, contains('SALA MISTERIOSA'));
      expect(item.divergencias, isEmpty, reason: 'bloqueado nunca chega a comparar campos');
    });

    test('setor presente na planilha mas não resolvido (nem por padrão) → BLOQUEADO', () {
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '123456', ImportColumnField.setor: 'Setor Desconhecido'},
        numeroPatrimonio: '123456',
        setorTexto: 'Setor Desconhecido',
        destinoIdResolvido: null,
        existenteNoBanco: _existente(),
      );

      final lote = PatrimonioComparador.comparar([linha]);

      expect(lote.itens.single.classificacao, ClassificacaoComparacao.bloqueado);
      expect(lote.itens.single.motivoBloqueio, contains('Setor'));
    });

    test('setor caiu no PADRÃO da importação (não veio da própria linha) → BLOQUEADO, nunca comparado ao padrão', () {
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '123456', ImportColumnField.setor: 'Setor Desconhecido'},
        numeroPatrimonio: '123456',
        setorTexto: 'Setor Desconhecido',
        destinoIdResolvido: 'setor-padrao-da-importacao',
        usouDestinoPadrao: true,
        existenteNoBanco: _existente(setorAtualId: 'setor-padrao-da-importacao'),
      );

      final lote = PatrimonioComparador.comparar([linha]);

      // Mesmo o padrão "coincidindo" com o setor atual do banco, isto NUNCA
      // vira "idêntico": a planilha não disse nada confiável para este
      // campo nesta linha.
      expect(lote.itens.single.classificacao, ClassificacaoComparacao.bloqueado);
    });
  });

  group('PatrimonioComparador — CENÁRIO 7: campo ausente ou vazio na planilha', () {
    test('coluna Marca não mapeada nesta importação → nunca comparada (nem idêntica, nem divergente)', () {
      final existente = _existente(marca: 'DELL');
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '123456'}, // sem ImportColumnField.marca
        numeroPatrimonio: '123456',
        marca: null,
        existenteNoBanco: existente,
      );

      final lote = PatrimonioComparador.comparar([linha]);

      expect(lote.itens.single.classificacao, ClassificacaoComparacao.identico);
      expect(lote.itens.single.divergencias.where((d) => d.campo == 'Marca'), isEmpty);
    });

    test('coluna Marca mapeada mas célula desta linha vazia → nunca interpretado como "apagar"', () {
      final existente = _existente(marca: 'DELL');
      final linha = _linha(
        celulas: {ImportColumnField.numeroPatrimonio: '123456', ImportColumnField.marca: null}, // mapeada, célula vazia
        numeroPatrimonio: '123456',
        marca: null,
        existenteNoBanco: existente,
      );

      final lote = PatrimonioComparador.comparar([linha]);

      expect(lote.itens.single.classificacao, ClassificacaoComparacao.identico);
      expect(lote.itens.single.divergencias, isEmpty);
    });
  });

  group('PatrimonioComparador — CENÁRIO 8: planilha grande (~500 patrimônios)', () {
    test('500 linhas mistas classificam corretamente e as contagens do resumo batem sem duplicar', () {
      final linhas = <ImportRow>[];
      // 200 idênticos.
      for (var i = 0; i < 200; i++) {
        final numero = 'EXIST-$i';
        linhas.add(
          _linha(
            numeroLinha: i + 2,
            celulas: {ImportColumnField.numeroPatrimonio: numero, ImportColumnField.descricao: 'Item $i'},
            numeroPatrimonio: numero,
            descricao: 'Item $i',
            existenteNoBanco: _existente(id: 'p-$i', numeroPatrimonio: numero, descricao: 'Item $i'),
          ),
        );
      }
      // 150 divergentes (descrição diferente).
      for (var i = 200; i < 350; i++) {
        final numero = 'EXIST-$i';
        linhas.add(
          _linha(
            numeroLinha: i + 2,
            celulas: {ImportColumnField.numeroPatrimonio: numero, ImportColumnField.descricao: 'Novo texto $i'},
            numeroPatrimonio: numero,
            descricao: 'Novo texto $i',
            existenteNoBanco: _existente(id: 'p-$i', numeroPatrimonio: numero, descricao: 'Item $i'),
          ),
        );
      }
      // 100 novos.
      for (var i = 350; i < 450; i++) {
        final numero = 'NOVO-$i';
        linhas.add(
          _linha(
            numeroLinha: i + 2,
            celulas: {ImportColumnField.numeroPatrimonio: numero},
            numeroPatrimonio: numero,
            existenteNoBanco: null,
          ),
        );
      }
      // 50 bloqueados (localização pendente).
      for (var i = 450; i < 500; i++) {
        final numero = 'BLOQ-$i';
        linhas.add(
          _linha(
            numeroLinha: i + 2,
            numeroPatrimonio: numero,
            localizacaoTexto: 'Desconhecida $i',
            localizacaoPendente: true,
            existenteNoBanco: _existente(id: 'q-$i', numeroPatrimonio: numero),
          ),
        );
      }
      expect(linhas, hasLength(500));

      final sw = Stopwatch()..start();
      final lote = PatrimonioComparador.comparar(linhas);
      sw.stop();

      expect(lote.resumo.totalLinhas, 500);
      expect(lote.resumo.identicos, 200);
      expect(lote.resumo.divergentes, 150);
      expect(lote.resumo.novos, 100);
      expect(lote.resumo.bloqueados, 50);
      // consistência: soma das categorias principais == total, sem sobra/duplicação.
      expect(lote.resumo.identicos + lote.resumo.divergentes + lote.resumo.novos + lote.resumo.bloqueados, 500);
      expect(lote.itensParaRevisao, hasLength(300)); // tudo, menos os 200 idênticos.
      expect(lote.resumo.divergenciasPorCampo['Descrição'], 150);
      // puro, em memória: não deve ser lento nem perto do que uma rede seria.
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('PatrimonioComparador — CENÁRIO 9: nenhuma escrita', () {
    test('comparar() é síncrono e não expõe nenhum método de escrita — comprovado pela própria assinatura', () {
      // PatrimonioComparador não recebe (nem poderia chamar) nenhum
      // PatrimonioRepository — a prova definitiva está na assinatura de
      // `comparar` (só List<ImportRow> → ComparacaoLote, sem I/O). Este
      // teste documenta essa garantia estrutural e roda como qualquer
      // outro caso, sem nenhum repositório fake presente na chamada.
      final lote = PatrimonioComparador.comparar([
        _linha(numeroPatrimonio: '1', existenteNoBanco: _existente(numeroPatrimonio: '1')),
      ]);
      expect(lote.resumo.totalLinhas, 1);
    });
  });
}
