import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_conclusao_lote_plano.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_selecao_aptos_lote.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

/// PROMPT 11.5.6 — planejamento PURO da conclusão em lote
/// (`planejarConclusaoLote`) e da ação "Concluir todos os aptos"
/// (`selecionarAptosParaLote`). Nenhum I/O, nenhum Supabase, nenhum
/// patrimônio do Despacho 577.
void main() {
  final documento = _documento(id: 'doc-1');

  group('planejarConclusaoLote — seleção válida', () {
    test('nenhum bloqueio, plano de cada item preservado, total selecionado correto', () {
      final itens = [_itemApto(id: 'item-1', patrimonioId: 'pat-1'), _itemApto(id: 'item-2', patrimonioId: 'pat-2')];

      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: itens,
        patrimoniosPorItemId: {'item-1': _patrimonio('pat-1'), 'item-2': _patrimonio('pat-2')},
      );

      expect(plano.podeConfirmar, isTrue);
      expect(plano.bloqueiosGerais, isEmpty);
      expect(plano.totalSelecionado, 2);
      expect(plano.algumItemBloqueado, isFalse);
      expect(plano.itens.map((i) => i.itemId), ['item-1', 'item-2']);
      // O plano de CADA item é o mesmo que planejarConclusaoEntrega geraria
      // sozinho — mesmo objeto de regras, sem duplicação de lógica.
      expect(plano.itens[0].plano.podeConfirmar, isTrue);
      expect(plano.itens[0].plano.numeroPatrimonio, 'PAT-item-1');
    });
  });

  group('planejarConclusaoLote — seleção vazia', () {
    test('bloqueada com motivo claro, nunca "sem itens" silencioso', () {
      final plano = planejarConclusaoLote(documento: documento, itensSelecionados: [], patrimoniosPorItemId: {});

      expect(plano.podeConfirmar, isFalse);
      expect(plano.totalSelecionado, 0);
      expect(plano.bloqueiosGerais, isNotEmpty);
      expect(plano.bloqueiosGerais.single, contains('Selecione ao menos um item'));
    });
  });

  group('planejarConclusaoLote — item bloqueado dentro da seleção', () {
    test('um único item bloqueado bloqueia o LOTE INTEIRO, mas nenhum item some da lista', () {
      final itens = [
        _itemApto(id: 'item-1', patrimonioId: 'pat-1'),
        // decisão de localização ainda PENDENTE — bloqueio técnico conhecido.
        _itemComDecisaoPendente(id: 'item-2', patrimonioId: 'pat-2'),
      ];

      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: itens,
        patrimoniosPorItemId: {'item-1': _patrimonio('pat-1'), 'item-2': _patrimonio('pat-2')},
      );

      // O lote inteiro fica bloqueado — nunca "conclui item-1 e ignora item-2".
      expect(plano.podeConfirmar, isFalse);
      expect(plano.algumItemBloqueado, isTrue);
      // NENHUM item foi removido da lista: os dois continuam presentes,
      // cada um com seu próprio plano/bloqueio visível.
      expect(plano.itens, hasLength(2));
      expect(plano.itens[0].plano.bloqueios, isEmpty);
      expect(plano.itens[1].plano.bloqueios, isNotEmpty);
    });
  });

  group('planejarConclusaoLote — seleção duplicada', () {
    test('o mesmo item repetido na seleção é bloqueado', () {
      final item = _itemApto(id: 'item-1', patrimonioId: 'pat-1');
      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: [item, item],
        patrimoniosPorItemId: {'item-1': _patrimonio('pat-1')},
      );

      expect(plano.podeConfirmar, isFalse);
      expect(plano.bloqueiosGerais, contains(contains('mesmo item repetido')));
    });

    test('dois itens diferentes apontando para o mesmo patrimônio são bloqueados', () {
      final itens = [_itemApto(id: 'item-1', patrimonioId: 'pat-x'), _itemApto(id: 'item-2', patrimonioId: 'pat-x')];
      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: itens,
        patrimoniosPorItemId: {'item-1': _patrimonio('pat-x'), 'item-2': _patrimonio('pat-x')},
      );

      expect(plano.podeConfirmar, isFalse);
      expect(plano.bloqueiosGerais, contains(contains('mesmo patrimônio')));
    });
  });

  group('planejarConclusaoLote — limite de 200 itens', () {
    test('mais de 200 itens selecionados bloqueia o lote (nunca trunca sozinho)', () {
      final itens = List.generate(
        limiteItensLote + 1,
        (i) => _itemApto(id: 'item-$i', patrimonioId: 'pat-$i'),
      );
      final plano = planejarConclusaoLote(documento: documento, itensSelecionados: itens, patrimoniosPorItemId: {});

      expect(plano.podeConfirmar, isFalse);
      expect(plano.totalSelecionado, limiteItensLote + 1);
      // A lista COMPLETA continua presente — nunca cortada para 200.
      expect(plano.itens, hasLength(limiteItensLote + 1));
      expect(plano.bloqueiosGerais, contains(contains('limite é de $limiteItensLote')));
    });

    test('exatamente 200 itens não dispara o bloqueio de limite', () {
      final itens = List.generate(limiteItensLote, (i) => _itemApto(id: 'item-$i', patrimonioId: 'pat-$i'));
      final plano = planejarConclusaoLote(documento: documento, itensSelecionados: itens, patrimoniosPorItemId: {});

      expect(plano.bloqueiosGerais.where((b) => b.contains('limite')), isEmpty);
    });
  });

  group('planejarConclusaoLote — não mistura documentos', () {
    test('item de outro documento na seleção é bloqueado', () {
      final itemDeOutro = _itemApto(id: 'item-x', patrimonioId: 'pat-x', documentoId: 'doc-2');
      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: [itemDeOutro],
        patrimoniosPorItemId: {'item-x': _patrimonio('pat-x')},
      );

      expect(plano.podeConfirmar, isFalse);
      expect(plano.bloqueiosGerais, contains(contains('documento diferente')));
    });
  });

  group('planejarConclusaoLote — confirmação de limpeza agregada', () {
    test('true quando QUALQUER item da seleção exigir, mesmo que os demais não exijam', () {
      final semLimpeza = _itemApto(id: 'item-1', patrimonioId: 'pat-1');
      final comLimpeza = _itemApto(
        id: 'item-2',
        patrimonioId: 'pat-2',
        decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
      );

      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: [semLimpeza, comLimpeza],
        patrimoniosPorItemId: {
          'item-1': _patrimonio('pat-1', comLocalizacao: false),
          'item-2': _patrimonio('pat-2', comLocalizacao: true),
        },
      );

      expect(plano.exigeConfirmacaoDeLimpezaAgregada, isTrue);
    });
  });

  group('selecionarAptosParaLote — Concluir todos os aptos', () {
    test('separa aptos de não incluídos, cada não incluído com motivo — nada some silenciosamente', () {
      final aptoA = _itemApto(id: 'a', patrimonioId: 'pat-a');
      final aptoB = _itemApto(id: 'b', patrimonioId: 'pat-b');
      final jaConcluido = _itemApto(id: 'c', patrimonioId: 'pat-c', status: SeiItemPendenciaStatus.concluido);
      final semDestino = _itemApto(id: 'd', patrimonioId: 'pat-d', destinoSetorId: null);
      final decisaoPendente = _itemComDecisaoPendente(id: 'e', patrimonioId: 'pat-e');

      final selecao = selecionarAptosParaLote([aptoA, aptoB, jaConcluido, semDestino, decisaoPendente]);

      expect(selecao.aptos.map((i) => i.id), unorderedEquals(['a', 'b']));
      expect(selecao.naoIncluidos.map((n) => n.item.id), unorderedEquals(['c', 'd', 'e']));
      // NUNCA um item não incluído sem explicação.
      for (final naoIncluido in selecao.naoIncluidos) {
        expect(naoIncluido.motivos, isNotEmpty, reason: 'item ${naoIncluido.item.id} sem motivo');
      }
      final motivoConcluido = selecao.naoIncluidos.firstWhere((n) => n.item.id == 'c').motivos;
      expect(motivoConcluido.single, contains('PENDENTE'));
      expect(selecao.excedeLimite, isFalse);
    });

    test('mais de 200 itens elegíveis: excedeLimite true, MAS a lista de aptos não é truncada', () {
      final itens = List.generate(limiteItensLote + 5, (i) => _itemApto(id: 'item-$i', patrimonioId: 'pat-$i'));
      final selecao = selecionarAptosParaLote(itens);

      expect(selecao.excedeLimite, isTrue);
      expect(selecao.aptos, hasLength(limiteItensLote + 5));
      expect(selecao.totalAptos, limiteItensLote + 5);
    });

    test('nenhum item elegível: aptos vazio, todos em naoIncluidos com motivo', () {
      final itens = [_itemApto(id: 'a', patrimonioId: 'pat-a', status: SeiItemPendenciaStatus.cancelado)];
      final selecao = selecionarAptosParaLote(itens);

      expect(selecao.aptos, isEmpty);
      expect(selecao.naoIncluidos, hasLength(1));
      expect(selecao.naoIncluidos.single.motivos.single, contains('Cancelado'));
    });
  });
}

SeiDocumentoPendente _documento({required String id}) {
  return SeiDocumentoPendente.fromItens(
    id: id,
    numeroDocumentoSei: 'SEI-$id',
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'despacho.pdf',
    hashSha256: 'hash-$id',
    versao: 1,
    criadoEm: DateTime.utc(2026, 1, 1),
    criadoPorId: 'user-1',
    criadoPorNome: 'Usuária de Teste',
  );
}

SeiItemPendente _itemApto({
  required String id,
  required String patrimonioId,
  String documentoId = 'doc-1',
  String? destinoSetorId = 'setor-ntat',
  SeiDecisaoCampo decisaoLocalizacao = SeiDecisaoCampo.confirmadoSemInformacao,
  SeiDecisaoCampo decisaoResponsavel = SeiDecisaoCampo.confirmadoSemInformacao,
  SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente,
}) {
  return SeiItemPendente(
    id: id,
    documentoId: documentoId,
    linha: 1,
    patrimonioId: patrimonioId,
    numeroPatrimonio: SeiValorCorrigivel(original: 'PAT-$id'),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
    origemSetorId: 'setor-getec',
    destinoTexto: const SeiValorCorrigivel(original: 'NTAT'),
    destinoSetorId: destinoSetorId,
    numeroChamado: const SeiValorCorrigivel(original: null),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Notebook'),
    decisaoLocalizacao: decisaoLocalizacao,
    decisaoResponsavel: decisaoResponsavel,
    status: status,
    criadoEm: DateTime.utc(2026, 1, 1),
  );
}

SeiItemPendente _itemComDecisaoPendente({required String id, required String patrimonioId}) =>
    _itemApto(id: id, patrimonioId: patrimonioId, decisaoLocalizacao: SeiDecisaoCampo.pendente);

PatrimonioDetalhe _patrimonio(String id, {bool comLocalizacao = false}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: 'PAT-$id',
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-getec',
      localizacaoAtualId: comLocalizacao ? 'localizacao-1' : null,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: 'Gerencia de Tecnologia',
    localizacaoNome: comLocalizacao ? 'Sala 1' : null,
  );
}
