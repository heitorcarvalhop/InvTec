import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_conclusao_erros.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_conclusao_item_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_conclusao_lote_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_pendencia_exceptions.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

import '../../patrimonios/fake_patrimonio_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// PROMPT 11.5.5 — contrato/domínio/repositório da conclusão em LOTE de
/// documentos SEI. NENHUM teste aqui fala com o Supabase real ou chama a
/// RPC `concluir_itens_documento_sei_lote` de verdade: a desserialização é
/// testada contra JSON MONTADO À MÃO no formato exato devolvido pela RPC
/// (ver `supabase/migrations/20260928100000_add_concluir_itens_documento_sei_lote.sql`,
/// já homologada — PROMPT 11.5.3), o envio de parâmetros é testado contra a
/// função PURA `paramsConclusaoLoteSei` (sem `SupabaseClient`), e o
/// comportamento de negócio (retry/P0036/P0037/contrato individual) usa
/// `FakeDocumentosSeiRepository`. Nenhum destes testes substitui a
/// homologação transacional real (11.5.3) contra o PostgreSQL de verdade.
void main() {
  group('SeiConclusaoLoteResultado.fromJson — envelope real da RPC', () {
    Map<String, dynamic> jsonItem({required String itemId, required int versao, bool jaConcluido = false}) => {
      'item_id': itemId,
      'resultado': {
        'ja_concluido': jaConcluido,
        'documento': {'id': 'doc-1', 'versao': versao},
        'item': _itemJson(id: itemId, status: 'CONCLUIDO'),
        'movimentacao': _movimentacaoJson(id: 'mov-$itemId'),
      },
    };

    test('primeira execução (ja_executado: false) — desserializa documento e itens na ordem recebida', () {
      final json = {
        'ja_executado': false,
        'documento': {'id': 'doc-1', 'versao': 3},
        'itens': [
          jsonItem(itemId: 'item-1', versao: 2),
          jsonItem(itemId: 'item-2', versao: 3),
        ],
      };

      final resultado = SeiConclusaoLoteResultado.fromJson(json);

      expect(resultado.jaExecutado, isFalse);
      expect(resultado.documentoId, 'doc-1');
      // A versão exposta é a do envelope (FINAL, depois de todos os itens),
      // não a de cada item individual.
      expect(resultado.documentoVersao, 3);
      expect(resultado.itens, hasLength(2));
      expect(resultado.itens[0].itemId, 'item-1');
      expect(resultado.itens[0].resultado.documentoVersao, 2);
      expect(resultado.itens[1].itemId, 'item-2');
      expect(resultado.itens[1].resultado.documentoVersao, 3);
    });

    test('retry idêntico (ja_executado: true) — mesmo formato, sem itens novos', () {
      final json = {
        'ja_executado': true,
        'documento': {'id': 'doc-9', 'versao': 5},
        'itens': [jsonItem(itemId: 'item-1', versao: 5)],
      };

      final resultado = SeiConclusaoLoteResultado.fromJson(json);

      expect(resultado.jaExecutado, isTrue);
      expect(resultado.documentoId, 'doc-9');
      expect(resultado.documentoVersao, 5);
    });

    test('lote vazio de itens (não deveria acontecer na prática, mas não deve estourar)', () {
      final json = {
        'ja_executado': false,
        'documento': {'id': 'doc-1', 'versao': 1},
        'itens': <dynamic>[],
      };

      expect(SeiConclusaoLoteResultado.fromJson(json).itens, isEmpty);
    });
  });

  group('SeiConclusaoLoteItemResultado.fromJson — reaproveita SeiConclusaoItemResultado', () {
    test('resultado interno usa EXATAMENTE o parser da conclusão individual', () {
      final json = {
        'item_id': 'item-7',
        'resultado': {
          'ja_concluido': false,
          'documento': {'id': 'doc-1', 'versao': 4},
          'item': _itemJson(id: 'item-7', status: 'CONCLUIDO'),
          'movimentacao': _movimentacaoJson(id: 'mov-7'),
        },
      };

      final elemento = SeiConclusaoLoteItemResultado.fromJson(json);

      expect(elemento.itemId, 'item-7');
      expect(elemento.resultado, isA<SeiConclusaoItemResultado>());
      expect(elemento.resultado.jaConcluido, isFalse);
      expect(elemento.resultado.documentoVersao, 4);
      expect(elemento.resultado.item.id, 'item-7');
      expect(elemento.resultado.movimentacao.id, 'mov-7');
    });
  });

  group('paramsConclusaoLoteSei — os seis parâmetros, nos nomes exatos da RPC', () {
    test('encaminha os seis parâmetros com os nomes esperados pela RPC', () {
      final params = paramsConclusaoLoteSei(
        documentoId: 'doc-1',
        itemIds: const ['item-1', 'item-2'],
        versaoEsperada: 3,
        loteId: 'lote-abc',
        observacao: 'entrega em lote',
        confirmarLimpezaDestino: true,
      );

      expect(params, {
        'p_documento_id': 'doc-1',
        'p_item_ids': ['item-1', 'item-2'],
        'p_versao_esperada': 3,
        'p_lote_id': 'lote-abc',
        'p_observacao': 'entrega em lote',
        'p_confirmar_limpeza_destino': true,
      });
    });

    test('observação em branco vira null (mesma normalização da conclusão individual)', () {
      final params = paramsConclusaoLoteSei(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: 'lote-abc',
        observacao: '   ',
      );

      expect(params['p_observacao'], isNull);
      // default de confirmarLimpezaDestino é false — nunca omitido do payload.
      expect(params['p_confirmar_limpeza_destino'], false);
    });

    test('nunca omite p_confirmar_limpeza_destino mesmo com o default', () {
      final params = paramsConclusaoLoteSei(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: 'lote-abc',
      );

      expect(params.containsKey('p_confirmar_limpeza_destino'), isTrue);
      expect(params['p_confirmar_limpeza_destino'], false);
    });
  });

  group('mensagemErroConclusaoSei — P0036 e P0037 (novos desta RPC)', () {
    test('P0036 — item indisponível para esta nova conclusão', () {
      final mensagem = mensagemErroConclusaoSei(codigo: 'P0036', mensagemDoServidor: 'algo técnico');
      expect(mensagem, contains('não estão mais disponíveis'));
      expect(mensagem, contains('Nada foi concluído'));
    });

    test('P0037 — lote_id reutilizado com parâmetros diferentes', () {
      final mensagem = mensagemErroConclusaoSei(codigo: 'P0037', mensagemDoServidor: 'algo técnico');
      expect(mensagem, contains('parâmetros diferentes'));
      expect(mensagem, contains('Não repita esta tentativa automaticamente'));
    });

    test('P0010 (conflito de versão) continua com a mensagem original — preservado', () {
      final mensagem = mensagemErroConclusaoSei(codigo: 'P0010', mensagemDoServidor: 'algo técnico');
      expect(mensagem, contains('alterado por outra pessoa'));
    });

    test('P0030 (código só da RPC individual) continua mapeado sem alteração', () {
      final mensagem = mensagemErroConclusaoSei(codigo: 'P0030', mensagemDoServidor: 'algo técnico');
      expect(mensagem, contains('estado deste item está inconsistente'));
    });
  });

  group('falhaDeConclusaoSei — operacao identifica qual RPC recusou', () {
    test('default preserva o comportamento anterior (RPC individual)', () {
      final falha = falhaDeConclusaoSei(codigo: 'P0010', mensagemDoServidor: 'x');
      expect(falha.operacao, operacaoConcluirItemSei);
    });

    test('operacao pode ser sobrescrita para a RPC de lote', () {
      final falha = falhaDeConclusaoSei(
        codigo: 'P0037',
        mensagemDoServidor: 'x',
        operacao: operacaoConcluirItensSeiLote,
      );
      expect(falha.operacao, operacaoConcluirItensSeiLote);
      expect(falha.textoTecnico, contains(operacaoConcluirItensSeiLote));
    });
  });

  group('PROMPT 11.5.14 — textoTecnicoConflitoDeIntegridade nunca orienta iniciar outra conclusão', () {
    test('nunca contém a orientação de "comece uma nova conclusão" (presente em textoTecnico/P0037)', () {
      final falha = falhaDeConclusaoSei(
        codigo: 'P0037',
        mensagemDoServidor: 'lote_id x já foi usado para uma operação com parâmetros diferentes',
        operacao: operacaoConcluirItensSeiLote,
      );

      // Prova a CAUSA do bug: `textoTecnico` (usado em qualquer OUTRO
      // painel) contém a orientação insegura — é exatamente o que
      // `textoTecnicoConflitoDeIntegridade` precisa NUNCA reproduzir aqui.
      expect(falha.textoTecnico, contains('comece uma nova conclusão'));

      final texto = textoTecnicoConflitoDeIntegridade(falha);
      expect(texto, isNot(contains('comece uma nova conclusão')));
      expect(texto, isNot(contains('nova conclusão')));
      expect(texto, isNot(contains('tente novamente')));
    });

    test('informa que a tentativa original está preservada e orienta contatar o suporte', () {
      final falha = falhaDeConclusaoSei(codigo: 'P0037', mensagemDoServidor: 'x', operacao: operacaoConcluirItensSeiLote);
      final texto = textoTecnicoConflitoDeIntegridade(falha);
      expect(texto, contains('permanece preservada'));
      expect(texto, contains('suporte técnico'));
      expect(texto, contains(operacaoConcluirItensSeiLote));
      expect(texto, contains('P0037'));
    });

    test('inclui o loteId quando informado — nunca observação/token/credencial', () {
      final falha = falhaDeConclusaoSei(codigo: 'P0037', mensagemDoServidor: 'x', operacao: operacaoConcluirItensSeiLote);
      final texto = textoTecnicoConflitoDeIntegridade(falha, loteId: 'lote-abc-123');
      expect(texto, contains('lote-abc-123'));
      expect(texto, isNot(contains('observação')));
      expect(texto, isNot(contains('token')));
      expect(texto, isNot(contains('credencial')));
    });

    test('sem loteId, nenhuma linha de identificador de lote aparece (nunca inventa um valor)', () {
      final falha = falhaDeConclusaoSei(codigo: 'P0037', mensagemDoServidor: 'x', operacao: operacaoConcluirItensSeiLote);
      final texto = textoTecnicoConflitoDeIntegridade(falha);
      expect(texto, isNot(contains('loteId')));
    });

    test('preserva detalhes/dica originais (já sanitizados) quando presentes', () {
      final falha = falhaDeConclusaoSei(
        codigo: 'P0037',
        mensagemDoServidor: 'detalhe técnico do servidor',
        operacao: operacaoConcluirItensSeiLote,
        dica: 'consulte o suporte',
      );
      final texto = textoTecnicoConflitoDeIntegridade(falha);
      expect(texto, contains('detalhe técnico do servidor'));
      expect(texto, contains('consulte o suporte'));
    });
  });

  group('FakeDocumentosSeiRepository.concluirItensLote', () {
    late FakeDocumentosSeiRepository repo;

    setUp(() {
      repo = FakeDocumentosSeiRepository(
        documentosIniciais: [_documento(id: 'doc-1', versao: 1, itens: [_item(id: 'item-1', patrimonioId: 'pat-2'), _item(id: 'item-2', patrimonioId: 'pat-1'), _item(id: 'item-3', patrimonioId: 'pat-3')])],
      );
    });

    test('primeira conclusão em lote — encadeia a versão e processa por patrimonio_id, não pela ordem enviada', () async {
      final resultado = await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-1', 'item-2'],
        versaoEsperada: 1,
        loteId: 'lote-1',
      );

      expect(resultado.jaExecutado, isFalse);
      expect(resultado.itens, hasLength(2));
      // item-2 (patrimonio pat-1) processado ANTES de item-1 (patrimonio
      // pat-2), mesmo enviado por último — mesma ordem da RPC real.
      expect(resultado.itens[0].itemId, 'item-2');
      expect(resultado.itens[1].itemId, 'item-1');
      // versão final = 1 (inicial) + 2 itens concluídos.
      expect(resultado.documentoVersao, 3);
      expect(repo.concluirCallCount, 2);

      final documento = await repo.obterPorId('doc-1');
      expect(documento.versao, 3);
      expect(documento.itens.firstWhere((i) => i.id == 'item-1').status, SeiItemPendenciaStatus.concluido);
      expect(documento.itens.firstWhere((i) => i.id == 'item-2').status, SeiItemPendenciaStatus.concluido);
      expect(documento.itens.firstWhere((i) => i.id == 'item-3').status, SeiItemPendenciaStatus.pendente);
    });

    test('retry idêntico (mesmo loteId e mesmos parâmetros) — devolve o resultado registrado, sem escrever de novo', () async {
      final primeira = await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-1', 'item-2'],
        versaoEsperada: 1,
        loteId: 'lote-1',
        observacao: '  entrega  ',
      );
      expect(primeira.jaExecutado, isFalse);
      final chamadasAntes = repo.concluirCallCount;

      final retry = await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-2', 'item-1'], // ordem diferente — canonicaliza igual
        versaoEsperada: 1,
        loteId: 'lote-1',
        observacao: 'entrega', // mesma observação, só sem espaços nas pontas
      );

      expect(retry.jaExecutado, isTrue);
      expect(retry.documentoId, primeira.documentoId);
      expect(retry.documentoVersao, primeira.documentoVersao);
      // NENHUMA nova chamada à RPC individual — nenhuma escrita nova.
      expect(repo.concluirCallCount, chamadasAntes);
    });

    test('mesmo loteId com seleção diferente → P0037, nunca reaproveitado silenciosamente', () async {
      await repo.concluirItensLote(documentoId: 'doc-1', itemIds: const ['item-1'], versaoEsperada: 1, loteId: 'lote-1');

      expect(
        () => repo.concluirItensLote(documentoId: 'doc-1', itemIds: const ['item-2'], versaoEsperada: 1, loteId: 'lote-1'),
        throwsA(isA<SeiEscritaFalhouException>().having((e) => e.codigo, 'codigo', 'P0037')),
      );
    });

    test('mesmo loteId com observação diferente → P0037', () async {
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: 'lote-1',
        observacao: 'A',
      );

      expect(
        () => repo.concluirItensLote(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          loteId: 'lote-1',
          observacao: 'B',
        ),
        throwsA(isA<SeiEscritaFalhouException>().having((e) => e.codigo, 'codigo', 'P0037')),
      );
    });

    test('mesmo loteId com confirmarLimpezaDestino diferente → P0037', () async {
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: 'lote-1',
      );

      expect(
        () => repo.concluirItensLote(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          loteId: 'lote-1',
          confirmarLimpezaDestino: true,
        ),
        throwsA(isA<SeiEscritaFalhouException>().having((e) => e.codigo, 'codigo', 'P0037')),
      );
    });

    test('item já concluído por FORA deste lote (individualmente) → P0036, lote inteiro recusado', () async {
      // item-2 concluído por uma chamada INDIVIDUAL antes do lote — nunca
      // conta como sucesso do lote (mesma regra da RPC real).
      await repo.concluirItem(documentoId: 'doc-1', itemId: 'item-2', versaoEsperada: 1);

      expect(
        () => repo.concluirItensLote(
          documentoId: 'doc-1',
          itemIds: const ['item-1', 'item-2'],
          versaoEsperada: 2,
          loteId: 'lote-novo',
        ),
        throwsA(isA<SeiEscritaFalhouException>().having((e) => e.codigo, 'codigo', 'P0036')),
      );

      // NADA do lote foi processado: item-1 continua PENDENTE.
      final documento = await repo.obterPorId('doc-1');
      expect(documento.itens.firstWhere((i) => i.id == 'item-1').status, SeiItemPendenciaStatus.pendente);
    });

    test('dois itens do lote com o mesmo patrimônio → P0001, nenhum é concluído', () async {
      repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento(
            id: 'doc-2',
            versao: 1,
            itens: [
              _item(id: 'a', patrimonioId: 'pat-x', documentoId: 'doc-2'),
              _item(id: 'b', patrimonioId: 'pat-x', documentoId: 'doc-2'),
            ],
          ),
        ],
      );

      expect(
        () => repo.concluirItensLote(documentoId: 'doc-2', itemIds: const ['a', 'b'], versaoEsperada: 1, loteId: 'lote-1'),
        throwsA(isA<SeiEscritaFalhouException>().having((e) => e.codigo, 'codigo', 'P0001')),
      );
    });

    test('itemIds repetido no array → P0001 (nunca deduplica silenciosamente)', () {
      expect(
        () => repo.concluirItensLote(
          documentoId: 'doc-1',
          itemIds: const ['item-1', 'item-1'],
          versaoEsperada: 1,
          loteId: 'lote-1',
        ),
        throwsA(isA<SeiEscritaFalhouException>().having((e) => e.codigo, 'codigo', 'P0001')),
      );
    });

    test('limite de 200 itens por chamada → P0001 acima disso', () {
      final idsDemais = List.generate(201, (i) => 'id-$i');
      expect(
        () => repo.concluirItensLote(documentoId: 'doc-1', itemIds: idsDemais, versaoEsperada: 1, loteId: 'lote-1'),
        throwsA(isA<SeiEscritaFalhouException>().having((e) => e.codigo, 'codigo', 'P0001')),
      );
    });

    test('versão desatualizada → P0010, nenhum item concluído', () async {
      expect(
        () => repo.concluirItensLote(documentoId: 'doc-1', itemIds: const ['item-1'], versaoEsperada: 99, loteId: 'lote-1'),
        throwsA(isA<SeiEscritaFalhouException>().having((e) => e.codigo, 'codigo', 'P0010')),
      );
      final documento = await repo.obterPorId('doc-1');
      expect(documento.itens.firstWhere((i) => i.id == 'item-1').status, SeiItemPendenciaStatus.pendente);
    });

    test('preserva a conclusão individual: concluirItem continua funcionando sem alteração de assinatura ou regra', () async {
      final resultadoIndividual = await repo.concluirItem(documentoId: 'doc-1', itemId: 'item-3', versaoEsperada: 1);

      expect(resultadoIndividual.jaConcluido, isFalse);
      expect(resultadoIndividual.item.status, SeiItemPendenciaStatus.concluido);
      expect(repo.concluirCallCount, 1);
      expect(repo.conclusoes.single['itemId'], 'item-3');

      // E o lote continua funcionando normalmente para os itens restantes.
      final resultadoLote = await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-1', 'item-2'],
        versaoEsperada: 2,
        loteId: 'lote-1',
      );
      expect(resultadoLote.itens, hasLength(2));
    });
  });

  group('PROMPT 11.5.9.2 — sincronização do cadastro patrimonial (FakePatrimonioRepository) após conclusão em lote', () {
    test(
      'lote com confirmarLimpezaDestino=true: setor atualizado para o destino, localização/responsável '
      'REALMENTE limpos, sem duplicar movimentação',
      () async {
        final patrimonios = FakePatrimonioRepository(
          itens: [_patrimonioComLimpeza(id: 'pat-23'), _patrimonioComLimpeza(id: 'pat-24')],
        );
        final repo = FakeDocumentosSeiRepository(
          documentosIniciais: [
            _documento(
              id: 'doc-1',
              versao: 1,
              itens: [_item(id: 'item-23', patrimonioId: 'pat-23'), _item(id: 'item-24', patrimonioId: 'pat-24')],
            ),
          ],
          patrimonioRepository: patrimonios,
        );

        // Antes: os dois patrimônios têm responsável e localização atuais —
        // exatamente o cenário que exige confirmarLimpezaDestino=true.
        final antes23 = await patrimonios.buscarDetalhePorId('pat-23');
        expect(antes23!.patrimonio.responsavelAtual, isNotNull);
        expect(antes23.patrimonio.localizacaoAtualId, isNotNull);

        final resultado = await repo.concluirItensLote(
          documentoId: 'doc-1',
          itemIds: const ['item-23', 'item-24'],
          versaoEsperada: 1,
          loteId: 'lote-limpeza',
          confirmarLimpezaDestino: true,
        );
        expect(resultado.itens, hasLength(2));

        // Itens SEI: CONCLUÍDO, com movimentacaoId — a parte que a
        // expansão do item SEI já mostrava corretamente (11.5.9.2, contexto).
        final documentoAtualizado = await repo.obterPorId('doc-1');
        for (final id in ['item-23', 'item-24']) {
          final item = documentoAtualizado.itens.firstWhere((i) => i.id == id);
          expect(item.status, SeiItemPendenciaStatus.concluido);
          expect(item.movimentacaoId, isNotNull);
        }

        // Cadastro patrimonial ATUALIZADO — o que faltava antes da correção.
        for (final id in ['pat-23', 'pat-24']) {
          final detalhe = await patrimonios.buscarDetalhePorId(id);
          expect(detalhe, isNotNull, reason: id);
          expect(detalhe!.patrimonio.setorAtualId, 'setor-ntat', reason: 'setor atualizado para o destino ($id)');
          expect(detalhe.patrimonio.localizacaoAtualId, isNull, reason: 'localização REALMENTE limpa ($id)');
          expect(detalhe.patrimonio.responsavelAtual, isNull, reason: 'responsável REALMENTE limpo ($id)');
          expect(detalhe.patrimonio.status, PatrimonioStatus.disponivel, reason: 'sem responsável => disponível ($id)');
        }

        // Nenhuma movimentação duplicada: uma chamada de conclusão por item,
        // um `movimentacaoId` cada — nunca dois registros para o mesmo item.
        expect(repo.concluirCallCount, 2);
        expect(repo.conclusoes.map((c) => c['itemId']).toSet(), {'item-23', 'item-24'});
      },
    );

    test('sem patrimonioRepository informado: conclusão continua funcionando, cadastro patrimonial nunca é tocado', () async {
      // Confirma que a sincronização é OPCIONAL — nenhum teste pré-existente
      // (que constrói FakeDocumentosSeiRepository sem esse parâmetro) é
      // afetado por esta correção.
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento(id: 'doc-1', versao: 1, itens: [_item(id: 'item-1', patrimonioId: 'pat-1')]),
        ],
      );
      final resultado = await repo.concluirItem(documentoId: 'doc-1', itemId: 'item-1', versaoEsperada: 1);
      expect(resultado.item.status, SeiItemPendenciaStatus.concluido);
    });

    test('item com decisão DEFINIDA (não limpeza): localização/responsável do patrimônio recebem o valor definido', () async {
      final patrimonios = FakePatrimonioRepository(itens: [_patrimonioComLimpeza(id: 'pat-30')]);
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento(
            id: 'doc-1',
            versao: 1,
            itens: [
              SeiItemPendente(
                id: 'item-30',
                documentoId: 'doc-1',
                linha: 1,
                patrimonioId: 'pat-30',
                numeroPatrimonio: const SeiValorCorrigivel(original: 'PAT-30'),
                origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
                origemSetorId: 'setor-getec',
                destinoTexto: const SeiValorCorrigivel(original: 'NTAT'),
                destinoSetorId: 'setor-ntat',
                numeroChamado: const SeiValorCorrigivel(original: null),
                equipamentoTexto: const SeiValorCorrigivel(original: 'Notebook'),
                localizacaoDestinoId: 'loc-nova',
                decisaoLocalizacao: SeiDecisaoCampo.definido,
                responsavelDestino: 'Fulano Novo',
                decisaoResponsavel: SeiDecisaoCampo.definido,
                status: SeiItemPendenciaStatus.pendente,
                criadoEm: DateTime.utc(2026, 1, 1),
              ),
            ],
          ),
        ],
        patrimonioRepository: patrimonios,
      );

      await repo.concluirItem(documentoId: 'doc-1', itemId: 'item-30', versaoEsperada: 1);

      final detalhe = await patrimonios.buscarDetalhePorId('pat-30');
      expect(detalhe!.patrimonio.setorAtualId, 'setor-ntat');
      expect(detalhe.patrimonio.localizacaoAtualId, 'loc-nova');
      expect(detalhe.patrimonio.responsavelAtual, 'Fulano Novo');
      expect(detalhe.patrimonio.status, PatrimonioStatus.emUso);
    });
  });
}

SeiDocumentoPendente _documento({required String id, required int versao, required List<SeiItemPendente> itens}) {
  return SeiDocumentoPendente.fromItens(
    id: id,
    numeroDocumentoSei: 'SEI-$id',
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'despacho.pdf',
    hashSha256: 'hash-$id',
    versao: versao,
    criadoEm: DateTime.utc(2026, 1, 1),
    criadoPorId: 'user-1',
    criadoPorNome: 'Usuária de Teste',
    itens: itens,
  );
}

SeiItemPendente _item({required String id, required String patrimonioId, String documentoId = 'doc-1'}) {
  return SeiItemPendente(
    id: id,
    documentoId: documentoId,
    linha: 1,
    patrimonioId: patrimonioId,
    numeroPatrimonio: SeiValorCorrigivel(original: 'PAT-$id'),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
    origemSetorId: 'setor-getec',
    destinoTexto: const SeiValorCorrigivel(original: 'NTAT'),
    destinoSetorId: 'setor-ntat',
    numeroChamado: const SeiValorCorrigivel(original: null),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Notebook'),
    decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
    decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
    status: SeiItemPendenciaStatus.pendente,
    criadoEm: DateTime.utc(2026, 1, 1),
  );
}

Map<String, dynamic> _itemJson({required String id, required String status}) => {
  'id': id,
  'documento_id': 'doc-1',
  'linha': 1,
  'patrimonio_id': 'pat-1',
  'numero_patrimonio_original': 'PAT-1',
  'numero_patrimonio_corrigido': null,
  'origem_texto_original': 'GETEC',
  'origem_setor_id': 'setor-getec',
  'destino_texto_original': 'NTAT',
  'destino_texto_corrigido': null,
  'destino_setor_id': 'setor-ntat',
  'numero_chamado_original': null,
  'numero_chamado_corrigido': null,
  'equipamento_texto_original': 'Notebook',
  'equipamento_texto_corrigido': null,
  'localizacao_destino_id': null,
  'decisao_localizacao': 'CONFIRMADO_SEM_INFORMACAO',
  'responsavel_destino': null,
  'decisao_responsavel': 'CONFIRMADO_SEM_INFORMACAO',
  'status': status,
  'motivo_cancelamento': null,
  'movimentacao_id': 'mov-$id',
  'corrigido_por': null,
  'corrigido_em': null,
  'motivo_correcao': null,
  'criado_em': '2026-01-01T00:00:00Z',
  'atualizado_em': null,
};

Map<String, dynamic> _movimentacaoJson({required String id}) => {
  'id': id,
  'patrimonio_id': 'pat-1',
  'tipo': 'TRANSFERENCIA',
  'origem_id': 'setor-getec',
  'destino_id': 'setor-ntat',
  'localizacao_origem_id': null,
  'localizacao_destino_id': null,
  'responsavel_origem': null,
  'responsavel_destino': null,
  'motivo': null,
  'observacao': null,
  'numero_documento': 'SEI-doc-1',
  'numero_chamado': null,
  'realizado_por': 'user-1',
  'data_movimentacao': '2026-01-01T00:00:00Z',
  'criado_em': '2026-01-01T00:00:00Z',
};

/// PROMPT 11.5.9.2 — patrimônio fictício com responsável/localização
/// ATUAIS já preenchidos (setor de ORIGEM, igual ao de [_item]) — o mesmo
/// cenário de DEMO-0023/DEMO-0024 na prévia local: concluir com
/// `confirmarLimpezaDestino: true` deve LIMPAR os dois de verdade no
/// cadastro fictício, não só na tela.
PatrimonioDetalhe _patrimonioComLimpeza({required String id}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: 'PAT-$id',
      tipoId: 'tipo-1',
      status: PatrimonioStatus.emUso,
      setorAtualId: 'setor-getec',
      responsavelAtual: 'Responsável Anterior $id',
      localizacaoAtualId: 'localizacao-anterior-$id',
      dataCadastro: DateTime.utc(2026, 1, 1),
      atualizadoEm: DateTime.utc(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: 'Gerência de Tecnologia',
    localizacaoNome: 'Sala anterior $id',
  );
}
