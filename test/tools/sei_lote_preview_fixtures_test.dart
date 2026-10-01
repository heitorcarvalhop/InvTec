import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_conclusao_lote_plano.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_selecao_aptos_lote.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

import 'sei_lote_preview_app.dart';

/// Regressão para o bug relatado ao testar a prévia
/// Windows: os fakes de `test/tools/sei_lote_preview_app.dart`
/// geravam o `origemSetorId` do item e o `setorAtualId` do patrimônio
/// fictício de formas INDEPENDENTES, então a maioria dos itens "elegíveis"
/// (inclusive DEMO-0001/DEMO-0002) ficava bloqueada por "Origem divergente"
/// sem nenhuma intenção disso.
///
/// Cobre também a correção de "Concluir todos os aptos"
/// (`_SeiPendenciaDetalheDialogState._concluirTodosAptos`), que agora
/// reavalia os candidatos da triagem por item contra o patrimônio ATUAL
/// antes de propor a seleção automática — DEMO-0018 (origem divergente)
/// não entra mais nela.
///
/// Este teste NUNCA reimplementa a regra de negócio: passa as fixtures da
/// prévia pelas MESMAS funções reais (`planejarConclusaoLote`,
/// `selecionarAptosParaLote`) que a tela usa — só prova que os DADOS
/// fictícios continuam coerentes com essas regras, nunca as regras em si
/// (`planejarConclusaoEntrega` não é tocado aqui).
void main() {
  final documento = documentoPreviewDemo();
  final patrimonios = {for (final p in patrimoniosPreviewDemo()) p.patrimonio.id: p};

  Map<String, PatrimonioDetalhe?> patrimoniosPorItemId(Iterable<String> itemIds) {
    return {
      for (final id in itemIds)
        id: patrimonios[documento.itens.firstWhere((i) => i.id == id).patrimonioId],
    };
  }

  group('coerência das fixtures da prévia', () {
    test('25 itens no total: 23 PENDENTES, 1 CONCLUÍDO, 1 CANCELADO', () {
      expect(documento.itens.length, 25);
      expect(documento.itens.where((i) => i.status == SeiItemPendenciaStatus.pendente).length, 23);
      expect(documento.itens.where((i) => i.status == SeiItemPendenciaStatus.concluido).length, 1);
      expect(documento.itens.where((i) => i.status == SeiItemPendenciaStatus.cancelado).length, 1);
    });

    test('DEMO-0001 e DEMO-0002 têm origem coerente com o setor atual do patrimônio e são elegíveis', () {
      final itens = documento.itens.where((i) => i.linha == 1 || i.linha == 2).toList();
      expect(itens, hasLength(2));
      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: itens,
        patrimoniosPorItemId: patrimoniosPorItemId(itens.map((i) => i.id)),
      );
      expect(plano.podeConfirmar, isTrue, reason: plano.bloqueiosGerais.join('; '));
      for (final item in plano.itens) {
        expect(item.plano.podeConfirmar, isTrue, reason: '${item.plano.numeroPatrimonio}: ${item.plano.bloqueios}');
        expect(item.plano.bloqueios, isEmpty);
      }
    });

    test('item 18 permanece BLOQUEADO por origem divergente, de propósito', () {
      final item18 = documento.itens.firstWhere((i) => i.linha == 18);
      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: [item18],
        patrimoniosPorItemId: patrimoniosPorItemId([item18.id]),
      );
      final planoItem = plano.itens.single.plano;
      expect(planoItem.podeConfirmar, isFalse);
      expect(planoItem.bloqueios.any((b) => b.contains('Origem divergente')), isTrue, reason: planoItem.bloqueios.join('; '));
      expect(plano.podeConfirmar, isFalse);
    });

    test('itens 23, 24 e 25 continuam exigindo confirmação de limpeza (responsável/localização)', () {
      final itens = documento.itens.where((i) => i.linha >= 23 && i.linha <= 25).toList();
      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: itens,
        patrimoniosPorItemId: patrimoniosPorItemId(itens.map((i) => i.id)),
      );
      expect(plano.exigeConfirmacaoDeLimpezaAgregada, isTrue);
      for (final item in plano.itens) {
        expect(item.plano.limpaResponsavel, isTrue);
        expect(item.plano.limpaLocalizacao, isTrue);
        expect(item.plano.podeConfirmar, isTrue, reason: item.plano.bloqueios.join('; '));
      }
    });

    test('triagem PRELIMINAR por item (selecionarAptosParaLote, pré-11.5.10): 21 aptos, 4 não incluídos', () {
      final selecao = selecionarAptosParaLote(documento.itens);
      // 21 = itens 1-17 (elegíveis normais) + 18 (origem divergente — não
      // detectável sem buscar o patrimônio, então esta triagem POR ITEM
      // sozinha ainda o inclui) + 23-25 (limpeza). 4 não incluídos =
      // 19/20 (decisão pendente) + 21 (concluído) + 22 (cancelado) — todos
      // detectáveis SEM buscar o patrimônio.
      expect(selecao.aptos.length, 21);
      expect(selecao.naoIncluidos.length, 4);
      expect(selecao.aptos.any((i) => i.linha == 1), isTrue);
      expect(selecao.aptos.any((i) => i.linha == 2), isTrue);
      // Confirma a premissa: esta triagem, sozinha, NÃO
      // detecta a origem divergente do item 18 (por isso a ação real
      // reavalia com o patrimônio, no teste seguinte).
      expect(selecao.aptos.any((i) => i.linha == 18), isTrue);
      final linhasNaoIncluidas = selecao.naoIncluidos.map((n) => n.item.linha).toSet();
      expect(linhasNaoIncluidas, {19, 20, 21, 22});
      expect(selecao.excedeLimite, isFalse);
    });

    test(
      '"Concluir todos os aptos" final (selecionarAptosParaLoteComPatrimonios): '
      '20 aptos, 5 não incluídos, DEMO-0018 EXCLUÍDO por origem divergente',
      () {
        // Chama DIRETO a função real usada por
        // `_SeiPendenciaDetalheDialogState._concluirTodosAptos`
        // (`sei_pendencia_detalhe_dialog.dart`) — nenhuma regra de
        // elegibilidade reproduzida à mão aqui.
        final selecao = selecionarAptosParaLoteComPatrimonios(
          documento: documento,
          patrimoniosPorItemId: patrimoniosPorItemId(documento.itens.map((i) => i.id)),
        );

        // 20 = 17 elegíveis normais + 23-25 (limpeza) — o item 18 SAIU.
        expect(selecao.aptos.length, 20);
        expect(selecao.excedeLimite, isFalse);
        expect(
          selecao.aptos.any((i) => i.linha == 18),
          isFalse,
          reason: 'DEMO-0018 não entra mais na seleção automática',
        );
        expect(selecao.aptos.any((i) => i.linha == 1), isTrue);
        expect(selecao.aptos.any((i) => i.linha == 2), isTrue);
        expect(selecao.aptos.any((i) => i.linha == 23), isTrue);
        expect(selecao.aptos.any((i) => i.linha == 24), isTrue);
        expect(selecao.aptos.any((i) => i.linha == 25), isTrue);

        // 5 não incluídos = 19/20 (decisão pendente) + 21 (concluído) + 22
        // (cancelado) + 18 (origem divergente), todos com motivo.
        expect(selecao.naoIncluidos, hasLength(5));
        final linhasNaoIncluidas = selecao.naoIncluidos.map((n) => n.item.linha).toSet();
        expect(linhasNaoIncluidas, {18, 19, 20, 21, 22});
        expect(
          selecao.naoIncluidos.firstWhere((n) => n.item.linha == 18).motivos.any((m) => m.contains('Origem divergente')),
          isTrue,
        );
      },
    );

    test('seleção EXPLÍCITA de DEMO-0018 continua bloqueando o lote inteiro (nunca removido silenciosamente)', () {
      final item18 = documento.itens.firstWhere((i) => i.linha == 18);
      final outroItem = documento.itens.firstWhere((i) => i.linha == 1);
      final plano = planejarConclusaoLote(
        documento: documento,
        itensSelecionados: [outroItem, item18],
        patrimoniosPorItemId: patrimoniosPorItemId([outroItem.id, item18.id]),
      );
      // Os DOIS itens aparecem no plano — nenhum é removido da seleção
      // explícita — mas o lote inteiro fica bloqueado por causa do item 18.
      expect(plano.itens, hasLength(2));
      expect(plano.podeConfirmar, isFalse);
      expect(plano.algumItemBloqueado, isTrue);
    });
  });
}
